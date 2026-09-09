class ReportScope
  # Colunas de valor que a tela de faturamento por subcanal deixa ordenar, com o rótulo que
  # levam no cabeçalho. A listagem vem inteira da consulta em cache: a ordem é aplicada na
  # leitura e nunca entra na chave do cache, senão cada clique viraria uma entrada nova.
  # A tela do recorrente ordena cards, não linhas: o card é o subcanal com a série dele.
  # Por isso as opções são valores da janela inteira, e não de um mês — "ordenar por débito"
  # não teria resposta única com seis competências por subcanal.
  RECURRING_SORT_COLUMNS = {
    "earnings" => "Ganho na janela",
    "last_month" => "Último mês fechado",
    "name" => "MIC"
  }.freeze

  SUB_CHANNEL_SORT_COLUMNS = {
    "previous_full_revenue" => "Mês anterior cheio",
    "previous_revenue" => "Mês anterior comparável",
    "current_revenue" => "Mês atual",
    "variation" => "Variação"
  }.freeze

  VIEWS = {
    stalled_companies: "audit_stalled_companies",
    weekly_revenue: "audit_weekly_revenue"
  }.freeze
  CHANNEL_PREDICATE = "(:channel_id IS NULL OR channel_id = :channel_id)".freeze

  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  # As agregações do dashboard só mudam numa consolidação ou num ajuste de corte, e os dois
  # tocam period_coverages: o carimbo dela na chave invalida o cache sozinho, como no
  # recorrente e no 3M. O corte entra porque o recorte do canal muda o dia de comparação.
  def revenue_by_sub_channel
    @revenue_by_sub_channel ||= cached("by_sub_channel") { aligned_revenue_by_sub_channel }
  end

  def revenue_by_establishment(sub_channel_id:, period: nil, from_day: nil, to_day: nil, **filters)
    listing = establishment_listing(sub_channel_id:, period:, from_day:, to_day:, **filters)
    listing ? listing.call : EstablishmentListingQuery.empty_page
  end

  # Mesmo recorte da tela sem a paginação: é o que a exportação leva.
  def establishment_rows(sub_channel_id:, period: nil, from_day: nil, to_day: nil, **filters)
    establishment_listing(sub_channel_id:, period:, from_day:, to_day:, **filters)&.all_rows || []
  end

  def contract_statuses(sub_channel_id:)
    sub_channel = SubChannel.find(sub_channel_id)
    channel_id = @channel_id || sub_channel.channel_id
    # EXISTS para em um snapshot por lote; o JOIN percorria todos os snapshots de todos os lotes.
    import_batch_id = ImportBatch.where(channel_id:, status: "validated")
      .where(RevenueSnapshot.where("revenue_snapshots.import_batch_id = import_batches.id").arel.exists)
      .maximum(:id)
    return [] unless import_batch_id

    RevenueSnapshot.where(import_batch_id:, sub_channel_id:).where.not(contract_status: [ nil, "" ])
      .distinct.order(:contract_status).pluck(:contract_status)
  end

  # Memoizado: a janela é montada para a tela e de novo para a listagem, no mesmo scope.
  def available_periods
    @available_periods ||= begin
      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
        SELECT period, max_known_day, closed
        FROM period_coverages
        WHERE #{CHANNEL_PREDICATE}
        ORDER BY period DESC
      SQL
      ApplicationRecord.connection.exec_query(sql).to_a
    end
  end

  def establishment_window(period: nil, from_day: nil, to_day: nil)
    PeriodWindow.from_coverages(available_periods, period:, from_day:, to_day:)
  end

  # Lançamentos diários de um EC, um dia por linha e as competências lado a lado — o mesmo
  # desenho da planilha, que traz DIA 01..DIA 31. A penúltima entra porque a leitura do
  # lançamento é comparativa: dois meses mostram a mudança, três mostram a tendência. O
  # arquivo traz duas competências; a mais antiga vem das importações anteriores, e por isso
  # a coluna só aparece quando a competência tem cobertura. O mês inteiro
  # aparece, não a faixa de dias dos filtros: o modal é a leitura do lançamento, não o
  # recorte da comparação. A série vem do generate_series porque dia sem venda precisa
  # aparecer zerado, senão o modal esconde exatamente o buraco que o usuário foi ver.
  SHEET_DAYS = 31

  def establishment_daily_revenues(establishment_id:, window:)
    return [] unless window

    binds = window.to_binds.merge(establishment_id:, from_day: 1, to_day: SHEET_DAYS)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      SELECT dias.day,
        COALESCE(SUM(revenue.amount) FILTER (WHERE revenue.period = :current_period), 0) AS current_amount,
        COALESCE(SUM(revenue.amount) FILTER (WHERE revenue.period = :previous_period), 0) AS previous_amount,
        COALESCE(SUM(revenue.amount) FILTER (WHERE revenue.period = :penultimate_period), 0) AS penultimate_amount
      FROM generate_series(:from_day::int, :to_day::int) AS dias(day)
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.day = dias.day
        AND revenue.establishment_id = :establishment_id
        AND revenue.period IN (:penultimate_period, :previous_period, :current_period)
      GROUP BY dias.day
      ORDER BY dias.day
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def stalled_companies
    query(:stalled_companies, "cnpj")
  end

  def recurring_earnings
    RecurringEarningsQuery.new(channel_id: @channel_id).by_sub_channel
  end

  def three_month_earnings(periods:)
    ThreeMonthEarningsQuery.new(periods:, channel_id: @channel_id).by_sub_channel
  end

  def three_month_establishments(periods:, sub_channel_id:)
    ThreeMonthEarningsQuery.new(periods:, channel_id: @channel_id).by_establishment(sub_channel_id:)
  end

  def weekly_revenue
    query(:weekly_revenue, "period, week")
  end

  # Faturamento de cada dia da competência, para o calendário. O generate_series vai até o
  # dia coberto pelo arquivo, e não até o fim do mês: dia coberto sem venda é zero — o buraco
  # que o usuário abre a tela para ver —, mas dia além da cobertura não tem linha nenhuma, e a
  # tela o mostra como "sem dado". Zero ali seria afirmar que a carteira não vendeu.
  def daily_calendar(period:, covered_days:)
    calendar_rows(<<~SQL, period:, covered_days:)
      SELECT dias.day,
        COALESCE(SUM(revenue.amount), 0) AS revenue,
        COUNT(DISTINCT revenue.establishment_id) FILTER (WHERE revenue.amount <> 0) AS establishments
      FROM generate_series(1, :covered_days::int) AS dias(day)
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.day = dias.day AND revenue.period = :period
        AND (:channel_id IS NULL OR revenue.channel_id = :channel_id)
      GROUP BY dias.day
      ORDER BY dias.day
    SQL
  end

  # Uma linha por semana de calendário, começando no domingo — a convenção do datepicker do
  # projeto. Os ECs são contados distintos na semana: somar os dias contaria o mesmo EC uma
  # vez por dia em que ele vendeu.
  def weekly_calendar(period:, covered_days:)
    calendar_rows(<<~SQL, period:, covered_days:)
      SELECT ((:period::date + (day - 1)) - EXTRACT(DOW FROM (:period::date + (day - 1)))::int) AS week_start,
        SUM(amount) AS revenue,
        COUNT(DISTINCT establishment_id) FILTER (WHERE amount <> 0) AS establishments
      FROM daily_revenues_consolidated
      WHERE period = :period AND day <= :covered_days::int
        AND (:channel_id IS NULL OR channel_id = :channel_id)
      GROUP BY 1
      ORDER BY 1
    SQL
  end

  # Quem vendeu num dia, por CNPJ: o cliente é a empresa, e um CNPJ pode ter vários ECs — daí
  # o GROUP BY na empresa e a contagem de ECs ao lado. O CNAE e o MIC vêm do snapshot mais
  # recente do Mapa; empresa sem snapshot devolve nulo, e a tela escreve travessão em vez de
  # inventar. Os dois saem em string_agg DISTINCT porque um CNPJ pode ter ECs em MICs
  # diferentes — é anomalia conhecida, detectada no import, e a tela mostra as duas.
  def day_companies(period:, day:)
    binds = { period:, day:, channel_id: @channel_id }
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      SELECT c.cnpj,
        MAX(mapa.legal_name) AS legal_name,
        string_agg(DISTINCT sub_channel.name, ' | ') AS sub_channels,
        string_agg(DISTINCT mapa.cnae_code || ' · ' || mapa.cnae_description, ' | ') AS cnaes,
        COUNT(DISTINCT revenue.establishment_id) AS establishments,
        SUM(revenue.amount) AS revenue
      FROM daily_revenues_consolidated revenue
      JOIN establishments e ON e.id = revenue.establishment_id
      JOIN companies c ON c.id = e.company_id
      LEFT JOIN LATERAL (
        SELECT legal_name, cnae_code, cnae_description, sub_channel_id
        FROM map_snapshots ms WHERE ms.establishment_id = e.id ORDER BY ms.id DESC LIMIT 1
      ) mapa ON TRUE
      LEFT JOIN sub_channels sub_channel ON sub_channel.id = mapa.sub_channel_id
      WHERE revenue.period = :period AND revenue.day = :day::int AND revenue.amount <> 0
        AND (:channel_id IS NULL OR revenue.channel_id = :channel_id)
      GROUP BY c.cnpj
      ORDER BY SUM(revenue.amount) DESC, c.cnpj
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  # Total da competência até um dia. O mesmo método serve ao mês escolhido e à âncora do mês
  # anterior — é o corte que muda, não a conta.
  def month_totals(period:, up_to_day:)
    calendar_rows(<<~SQL, period:, covered_days: up_to_day).first
      SELECT COALESCE(SUM(amount), 0) AS revenue,
        COUNT(DISTINCT establishment_id) FILTER (WHERE amount <> 0) AS establishments
      FROM daily_revenues_consolidated
      WHERE period = :period AND day <= :covered_days::int
        AND (:channel_id IS NULL OR channel_id = :channel_id)
    SQL
  end

  # Menor corte entre os canais do recorte: comparar períodos de durações diferentes
  # entre canais distorceria a variação.
  def cutoff_day
    coverages.map { |row| row["max_known_day"].to_i }.min
  end

  def mixed_cutoffs?
    coverages.map { |row| row["max_known_day"].to_i }.uniq.size > 1
  end

  def totals
    cutoff = cutoff_day
    return empty_totals unless cutoff

    cached("totals") { aligned_totals(cutoff) }
  end

  private

  def calendar_rows(sql, period:, covered_days:)
    binds = { period:, covered_days:, channel_id: @channel_id }
    ApplicationRecord.connection.exec_query(ApplicationRecord.sanitize_sql_array([ sql, binds ])).to_a
  end

  def cached(name, &block)
    Rails.cache.fetch([ "dashboard", name, PeriodCoverage.consolidation_stamp, @channel_id, cutoff_day ], &block)
  end

  def aligned_totals(cutoff)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id, cutoff: cutoff.to_i } ])
      WITH open_cover AS (
        SELECT channel_id, period, max_known_day,
          (period - INTERVAL '1 month')::date AS previous_period
        FROM period_coverages
        WHERE NOT closed AND #{CHANNEL_PREDICATE}
      )
      SELECT #{AuditViews.aligned_aggregates_sql(
        table: "dr", previous_period: "oc.previous_period", current_period: "oc.period",
        day_filter: "dr.day <= :cutoff"
      ).indent(4).strip}
      FROM daily_revenues_consolidated dr
      JOIN open_cover oc ON oc.channel_id = dr.channel_id
      WHERE dr.period IN (oc.previous_period, oc.period)
    SQL
    row = ApplicationRecord.connection.exec_query(sql).first || {}
    {
      previous_full_revenue: row["previous_full_revenue"].to_d,
      previous_revenue: row["previous_revenue"].to_d,
      current_revenue: row["current_revenue"].to_d
    }
  end

  def establishment_listing(sub_channel_id:, period:, from_day:, to_day:, **filters)
    window = establishment_window(period:, from_day:, to_day:)
    return unless window

    EstablishmentListingQuery.new(channel_id: @channel_id, sub_channel_id:, window:, **filters)
  end

  def empty_totals
    { previous_full_revenue: 0.to_d, previous_revenue: 0.to_d, current_revenue: 0.to_d }
  end

  def aligned_revenue_by_sub_channel
    cutoff = cutoff_day
    return [] unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([
      "#{AuditViews.revenue_by_sub_channel_sql(cutoff: ':cutoff', channel_predicate: CHANNEL_PREDICATE)} " \
        "ORDER BY sub_channel.name",
      { channel_id: @channel_id, cutoff: cutoff.to_i }
    ])
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def coverages
    @coverages ||= begin
      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
        SELECT channel_id, max_known_day FROM period_coverages
        WHERE NOT closed AND #{CHANNEL_PREDICATE}
      SQL
      ApplicationRecord.connection.exec_query(sql).to_a
    end
  end

  def query(name, order_by = nil)
    table = VIEWS.fetch(name)
    # Banco recém-criado carrega as views WITH NO DATA e consultá-las levanta erro;
    # até o primeiro import o relatório é legitimamente vazio.
    return [] unless AuditViews.populated?(table)

    sql = +"SELECT * FROM #{table}"
    sql << " WHERE channel_id = #{ApplicationRecord.connection.quote(@channel_id)}" if @channel_id
    sql << " ORDER BY #{order_by}" if order_by
    ApplicationRecord.connection.exec_query(sql).to_a
  end
end
