# Listagem paginada de estabelecimentos de um subcanal, com os dois meses alinhados
# pela mesma faixa de dias. Duas consultas por página: o resumo (contagens, totais da
# aba e totais gerais) numa passada só, e as linhas da página.
class EstablishmentListingQuery
  DATE_KINDS = {
    "credenciamento" => "mapa.accredited_on",
    "ativacao" => "mapa.activated_on",
    "suspensao" => "mapa.suspended_on"
  }.freeze
  PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
  DEFAULT_PER_PAGE = 20

  # Abas por variação alinhada. "Novo" de verdade é só quem foi ativado neste mês ou no
  # anterior (na falta da ativação, vale o credenciamento): EC antigo que estava zerado e
  # voltou a vender não é crescimento — é atenção, e cai na aba de queda. Sem nenhuma das
  # datas, não dá para provar que é novo: também cai na queda.
  RECENT_ACTIVATION = "COALESCE(activated_on, accredited_on) >= :previous_period".freeze
  VARIATION_CLAUSES = {
    "alta" => "current_revenue > 0 AND current_revenue >= previous_revenue " \
      "AND (previous_revenue > 0 OR #{RECENT_ACTIVATION})",
    "baixa" => "current_revenue = 0 OR current_revenue < previous_revenue " \
      "OR (previous_revenue = 0 AND current_revenue > 0 " \
      "AND (COALESCE(activated_on, accredited_on) IS NULL " \
      "OR COALESCE(activated_on, accredited_on) < :previous_period))"
  }.freeze

  def initialize(channel_id:, sub_channel_id:, window:, statuses: [], date_kinds: [],
    from_date: nil, to_date: nil, query: nil, variation: nil, page: 1, per_page: nil)
    @channel_id = channel_id
    @sub_channel_id = sub_channel_id
    @window = window
    @statuses = Array(statuses).map(&:to_s).compact_blank.uniq
    @date_kinds = Array(date_kinds).map(&:to_s) & DATE_KINDS.keys
    @from_date = parse_date(from_date)
    @to_date = parse_date(to_date)
    @from_date, @to_date = @to_date, @from_date if inverted_range?
    @query = query.to_s.strip
    @variation = variation.to_s.presence_in(VARIATION_CLAUSES.keys)
    @page = page
    @per_page = per_page
  end

  def self.empty_page
    EstablishmentRevenuePage.new(
      rows: [], total_count: 0, page: 1, per_page: DEFAULT_PER_PAGE,
      totals: { previous_full_revenue: 0.to_d, previous_revenue: 0.to_d, current_revenue: 0.to_d },
      variation_counts: { todas: 0, alta: 0, baixa: 0 }
    )
  end

  def call
    summary = fetch_summary
    page, per_page = normalize_page(summary[:total_count])

    EstablishmentRevenuePage.new(
      rows: fetch_rows(page, per_page), total_count: summary[:total_count],
      totals: summary[:totals], page:, per_page:, variation_counts: summary[:variation_counts],
      status_counts: summary[:status_counts], overall_totals: summary[:overall_totals]
    )
  end

  # Todas as linhas do recorte, na mesma ordem da tela e sem paginação.
  def all_rows
    ApplicationRecord.connection.exec_query(
      ApplicationRecord.sanitize_sql_array([ rows_sql, binds ])
    ).to_a
  end

  private

  def binds
    @binds ||= begin
      values = @window.to_binds.merge(
        channel_id: @channel_id, sub_channel_id: @sub_channel_id, statuses: @statuses
      )
      values.merge!(from_date: @from_date, to_date: @to_date) if lifecycle_filter?
      values.merge(search_binds)
    end
  end

  def lifecycle_filter?
    @from_date.present? && @to_date.present?
  end

  # Intervalo escolhido sem tipo de data marcado vale para os três tipos.
  def active_date_kinds
    return [] unless lifecycle_filter?

    @date_kinds.presence || DATE_KINDS.keys
  end

  def inverted_range?
    @from_date && @to_date && @to_date < @from_date
  end

  def search_binds
    return { query: nil, query_digits: nil } if @query.blank?

    digits = SearchNormalizer.digits(@query)
    {
      query: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%",
      query_digits: digits && "%#{ActiveRecord::Base.sanitize_sql_like(digits)}%"
    }
  end

  # Uma passada só sobre a listagem agregada resolve o resumo inteiro; antes eram três
  # (aba, contagens e totais gerais), cada uma refazendo o GROUP BY.
  def fetch_summary
    row = ApplicationRecord.connection.exec_query(summary_sql).first || {}
    {
      total_count: row["total_count"].to_i,
      totals: {
        previous_full_revenue: row["previous_full_revenue"].to_d,
        previous_revenue: row["previous_revenue"].to_d,
        current_revenue: row["current_revenue"].to_d
      },
      variation_counts: { todas: row["todas"].to_i, alta: row["alta"].to_i, baixa: row["baixa"].to_i },
      status_counts: {
        "Active" => row["active_count"].to_i, "Suspended" => row["suspended_count"].to_i
      },
      overall_totals: @variation && {
        previous_revenue: row["overall_previous_revenue"].to_d,
        current_revenue: row["overall_current_revenue"].to_d
      }
    }
  end

  # Decisão do usuário: os totais da primeira dobra seguem a aba ativa, somando só o que
  # a tabela lista. Vale saber que na aba Alta a variação sai positiva por construção (a
  # aba filtra pela própria métrica) — por isso a tela rotula o recorte no card, e os
  # totais sem o filtro de aba ancoram a variação verdadeira do recorte. As contagens das
  # três abas respeitam os demais filtros, nunca a própria aba — senão não fechariam.
  #
  # As abas contam estabelecimentos, identificados pelo CNPJ, não linhas: um estabelecimento
  # com dois ECs conta um no rótulo e ocupa duas linhas na tabela (decisão do usuário). Os
  # totais em dinheiro continuam somando linha a linha — cada EC tem faturamento próprio,
  # então somar por EC e somar por CNPJ dão o mesmo número; só a contagem muda. O total_count
  # segue contando linhas, porque é ele que pagina.
  def summary_sql
    ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      SELECT COUNT(*) FILTER (WHERE #{tab_clause}) AS total_count,
        COALESCE(SUM(previous_full_revenue) FILTER (WHERE #{tab_clause}), 0) AS previous_full_revenue,
        COALESCE(SUM(previous_revenue) FILTER (WHERE #{tab_clause}), 0) AS previous_revenue,
        COALESCE(SUM(current_revenue) FILTER (WHERE #{tab_clause}), 0) AS current_revenue,
        COUNT(*) FILTER (WHERE (#{tab_clause}) AND contract_status = 'Active') AS active_count,
        COUNT(*) FILTER (WHERE (#{tab_clause}) AND contract_status = 'Suspended') AS suspended_count,
        COUNT(DISTINCT cnpj) AS todas,
        COUNT(DISTINCT cnpj) FILTER (WHERE #{VARIATION_CLAUSES['alta']}) AS alta,
        COUNT(DISTINCT cnpj) FILTER (WHERE #{VARIATION_CLAUSES['baixa']}) AS baixa,
        COALESCE(SUM(previous_revenue), 0) AS overall_previous_revenue,
        COALESCE(SUM(current_revenue), 0) AS overall_current_revenue
      FROM (#{listing_sql}) listings
    SQL
  end

  def fetch_rows(page, per_page)
    sql = ApplicationRecord.sanitize_sql_array([
      "#{rows_sql} LIMIT :per_page OFFSET :offset",
      binds.merge(per_page:, offset: (page - 1) * per_page)
    ])
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def rows_sql
    "SELECT * FROM (#{listing_sql}) listings #{variation_where} ORDER BY ec, establishment_id"
  end

  def tab_clause
    @variation ? VARIATION_CLAUSES.fetch(@variation) : "TRUE"
  end

  def variation_where
    @variation ? "WHERE #{VARIATION_CLAUSES.fetch(@variation)}" : ""
  end

  def normalize_page(total_count)
    size = @per_page.to_i
    size = DEFAULT_PER_PAGE unless size.positive?
    size = PER_PAGE_OPTIONS.max if size > PER_PAGE_OPTIONS.max
    total_pages = [ (total_count.to_f / size).ceil, 1 ].max
    [ [ [ @page.to_i, 1 ].max, total_pages ].min, size ]
  end

  def listing_sql
    <<~SQL
      WITH #{AuditViews.latest_batches_sql(channel_predicate: "(:channel_id IS NULL OR ib.channel_id = :channel_id)").strip}
      SELECT snapshot.channel_id, snapshot.sub_channel_id, establishment.id AS establishment_id,
        establishment.uuid AS establishment_uuid,
        establishment.ec, company.cnpj, snapshot.legal_name, snapshot.trade_name,
        snapshot.contract_status, mapa.accredited_on, mapa.activated_on,
        mapa.suspended_on, mapa.has_payment_link, mapa.smart_pos_count, mapa.other_pos_count,
        mapa.tap_on_phone_count, mapa.mps_count, mapa.pin_count, mapa.tef_count,
        mapa.other_terminals_count, mapa.net_mdr, mapa.net_mdr_status,
        snapshot.previous_month_total, snapshot.current_month_total,
        :previous_period AS previous_period, :current_period AS current_period,
        :to_day AS max_known_day,
        #{AuditViews.aligned_aggregates_sql(
          table: "revenue", previous_period: ":previous_period", current_period: ":current_period",
          day_filter: "revenue.day BETWEEN :from_day AND :to_day"
        ).indent(4).strip}
      FROM revenue_snapshots snapshot
      JOIN latest_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      LEFT JOIN LATERAL (
        SELECT mapa.accredited_on, mapa.activated_on, mapa.suspended_on,
          mapa.has_payment_link, mapa.smart_pos_count, mapa.other_pos_count,
          mapa.tap_on_phone_count, mapa.mps_count, mapa.pin_count, mapa.tef_count,
          mapa.other_terminals_count, mapa.net_mdr, mapa.net_mdr_status
        FROM map_snapshots mapa
        WHERE mapa.establishment_id = establishment.id
          AND mapa.import_batch_id = snapshot.import_batch_id
        ORDER BY mapa.id DESC
        LIMIT 1
      ) mapa ON true
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = snapshot.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.period IN (:previous_period, :current_period)
      WHERE snapshot.sub_channel_id = :sub_channel_id
        #{status_clause}
        #{lifecycle_clause}
        #{search_clause}
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, establishment.id, establishment.ec,
        company.cnpj, snapshot.legal_name, snapshot.trade_name, snapshot.contract_status,
        mapa.accredited_on, mapa.activated_on, mapa.suspended_on, mapa.has_payment_link,
        mapa.smart_pos_count, mapa.other_pos_count, mapa.tap_on_phone_count, mapa.mps_count,
        mapa.pin_count, mapa.tef_count, mapa.other_terminals_count,
        mapa.net_mdr, mapa.net_mdr_status,
        snapshot.previous_month_total, snapshot.current_month_total
    SQL
  end

  def status_clause
    @statuses.any? ? "AND snapshot.contract_status IN (:statuses)" : ""
  end

  def lifecycle_clause
    columns = active_date_kinds.filter_map { |kind| DATE_KINDS[kind] }
    return "" if columns.empty?

    "AND (#{columns.map { |column| "#{column} BETWEEN :from_date AND :to_date" }.join(' OR ')})"
  end

  def search_clause
    return "" if binds[:query].blank?

    <<~SQL.squish
      AND (
        establishment.ec ILIKE :query
        OR snapshot.legal_name ILIKE :query
        OR snapshot.trade_name ILIKE :query
        OR company.cnpj ILIKE :query
        OR (
          :query_digits IS NOT NULL
          AND (company.cnpj ILIKE :query_digits OR establishment.ec ILIKE :query_digits)
        )
      )
    SQL
  end

  def parse_date(value)
    return if value.blank?
    return value.to_date if value.respond_to?(:to_date)

    Date.parse(value.to_s)
  rescue Date::Error, ArgumentError, TypeError
    nil
  end
end
