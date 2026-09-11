# Listagem paginada de estabelecimentos de um subcanal, com os dois meses alinhados
# pela mesma faixa de dias. Duas consultas por página: o resumo (contagens, totais da
# aba e totais gerais) numa passada só, e as linhas da página.
class EstablishmentListingQuery
  # Datas do ciclo do cliente, agregadas a partir dos ECs dele: entrou na mais antiga, e os
  # dois fatos do presente — suspensão e uso do app — ficam com a mais recente. Um EC novo
  # não rejuvenesce o credenciamento do cliente.
  #
  # A regra está escrita uma vez porque o SELECT a projeta e o HAVING a compara. Se as duas
  # divergirem, o filtro passa a escolher a linha por um valor diferente do que a linha
  # mostra — quem filtrasse "credenciados em agosto" veria uma linha dizendo fevereiro.
  CLIENT_DATES = {
    "accredited_on" => "MIN(accredited_on)",
    "activated_on" => "MIN(activated_on)",
    "suspended_on" => "MAX(suspended_on)",
    "last_app_access_at" => "MAX(last_app_access_at)"
  }.freeze
  # Status do cliente, pela mesma razão: Ativo se ao menos um EC estiver ativo, suspenso
  # quando todos estão (decisão do usuário, 07/09/2026 — oito dos nove CNPJs com status
  # misto da carteira são troca de EC, o antigo suspenso e o novo aberto no lugar).
  CLIENT_STATUS = "CASE WHEN bool_or(contract_status = 'Active') THEN 'Active' " \
    "ELSE MIN(contract_status) END".freeze
  DATE_KINDS = {
    "credenciamento" => "accredited_on",
    "ativacao" => "activated_on",
    "suspensao" => "suspended_on"
  }.freeze
  PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
  DEFAULT_PER_PAGE = 20

  # Colunas que a tela deixa ordenar, com o rótulo que a coluna leva. A lista é fechada
  # porque o valor vira SQL: qualquer coisa fora dela cai na ordem padrão.
  SORT_COLUMNS = {
    "previous_full_revenue" => "Mês anterior cheio",
    "previous_revenue" => "Mês anterior comparável",
    "current_revenue" => "Mês atual"
  }.freeze
  SORT_DIRECTIONS = %w[desc asc].freeze
  # A tela abre pelo mês anterior cheio, do maior para o menor: é a única coluna com valor
  # em toda competência — o mês atual fica zerado até a planilha do mês chegar — e a
  # primeira pergunta de uma auditoria é quem mais fatura. Ordem por EC não responde nada.
  DEFAULT_SORT = "previous_full_revenue".freeze
  DEFAULT_DIRECTION = "desc".freeze

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
    from_date: nil, to_date: nil, query: nil, variation: nil, sort: nil, direction: nil,
    page: 1, per_page: nil)
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
    @order = self.class.listing_sort(column: sort, direction:)

    @page = page
    @per_page = per_page
  end

  # A tela e a consulta falam do mesmo objeto de ordenação: uma lista fechada só.
  def self.listing_sort(column: nil, direction: nil)
    ListingSort.new(columns: SORT_COLUMNS, default: DEFAULT_SORT,
      default_direction: DEFAULT_DIRECTION, column:, direction:)
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
      status_counts: status_counts(row),
      overall_totals: @variation && {
        previous_revenue: row["overall_previous_revenue"].to_d,
        current_revenue: row["overall_current_revenue"].to_d
      }
    }
  end

  # O suspenso é o que sobra, e não uma contagem própria: a regra de status do cliente vive
  # em CLIENT_STATUS, e aqui só se conta quem saiu dela como ativo. O contrato tem dois
  # status (EstablishmentsHelper::CONTRACT_STATUSES); se surgir um terceiro, ele cai em
  # suspensos e este cálculo precisa mudar.
  def status_counts(row)
    clientes = row["total_count"].to_i
    active = row["active_count"].to_i
    { "Active" => active, "Suspended" => clientes - active }
  end

  # Decisão do usuário: os totais da primeira dobra seguem a aba ativa, somando só o que
  # a tabela lista. Vale saber que na aba Alta a variação sai positiva por construção (a
  # aba filtra pela própria métrica) — por isso a tela rotula o recorte no card, e os
  # totais sem o filtro de aba ancoram a variação verdadeira do recorte. As contagens das
  # três abas respeitam os demais filtros, nunca a própria aba — senão não fechariam.
  #
  # Abas, status e paginação contam a mesma coisa desde que a linha passou a ser o cliente:
  # COUNT(*) sobre a listagem agrupada é o número de CNPJs. Antes eram duas contagens
  # diferentes na mesma consulta — linhas para paginar, CNPJs distintos para rotular.
  def summary_sql
    ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      SELECT COUNT(*) FILTER (WHERE #{tab_clause}) AS total_count,
        COALESCE(SUM(previous_full_revenue) FILTER (WHERE #{tab_clause}), 0) AS previous_full_revenue,
        COALESCE(SUM(previous_revenue) FILTER (WHERE #{tab_clause}), 0) AS previous_revenue,
        COALESCE(SUM(current_revenue) FILTER (WHERE #{tab_clause}), 0) AS current_revenue,
        COUNT(*) FILTER (
          WHERE (#{tab_clause}) AND contract_status = 'Active'
        ) AS active_count,
        COUNT(*) AS todas,
        COUNT(*) FILTER (WHERE #{VARIATION_CLAUSES['alta']}) AS alta,
        COUNT(*) FILTER (WHERE #{VARIATION_CLAUSES['baixa']}) AS baixa,
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
    "SELECT * FROM (#{listing_sql}) listings #{variation_where} ORDER BY #{order_by}"
  end

  # O CNPJ é o desempate: sem ele, linhas de mesmo valor trocariam de lugar entre páginas a
  # cada consulta. Era o EC, que deixou de existir na linha.
  def order_by
    @order.sql_order_by(tiebreak: "cnpj")
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

  # A linha da listagem é o cliente, não o ponto de venda: uma linha por CNPJ, somando o
  # faturamento de todos os ECs dele (decisão do usuário, 10/09/2026). Na carteira real
  # isso leva 470 linhas a 302, e nenhum CNPJ aparece em dois MICs — medido —, então
  # agrupar dentro do subcanal é o mesmo que agrupar por CNPJ.
  #
  # São dois níveis de propósito. Agregar por CNPJ direto na consulta de dentro não
  # serviria: ela já está aberta pelo JOIN com daily_revenues_consolidated (uma linha por
  # EC por dia), e COUNT e agregados de cadastro sairiam multiplicados pelos dias.
  def listing_sql
    <<~SQL
      SELECT channel_id, sub_channel_id, cnpj, company_uuid,
        MAX(note_id) AS note_id, MAX(note_updated_at) AS note_updated_at,
        COUNT(*) AS ec_count,
        -- Nome do cliente pelo valor mais frequente entre os ECs, com o alfabético como
        -- desempate do mode(). Na carteira real 3 CNPJs têm razão social divergente entre
        -- os ECs e 2 têm nome fantasia; MAX pegaria o maior alfabeticamente, que não é o
        -- mais provável — foi assim que a Clover Capital trocou razão social por nome
        -- fantasia antes de passar a usar mode().
        mode() WITHIN GROUP (ORDER BY legal_name) AS legal_name,
        mode() WITHIN GROUP (ORDER BY trade_name) AS trade_name,
        #{CLIENT_STATUS} AS contract_status,
        #{client_dates_select},
        -- Só MDR positivo, por pedido do usuário: dos 470 ECs da carteira, 253 chegam
        -- "Inativo", 4 negativos e 2 zerados — nenhum desses afirma alíquota nenhuma.
        -- Os dois extremos, e não um valor só, porque 5 CNPJs têm dois MDR positivos
        -- diferentes entre os ECs, e num deles a diferença vai de 0,62% a 2,53%.
        MIN(net_mdr) FILTER (WHERE net_mdr > 0) AS net_mdr_min,
        MAX(net_mdr) FILTER (WHERE net_mdr > 0) AS net_mdr_max,
        -- A melhor conversa é de cada EC, e 116 dos 302 clientes têm mais de um texto
        -- diferente: vão todos, rotulados pelo EC, em vez de um escolhido a esmo.
        -- BTRIM + NULLIF porque texto só com espaço não é conversa: a tela antiga fazia
        -- strip antes de decidir, e sem isso o botão habilitaria para abrir um modal vazio.
        json_agg(json_build_object('ec', ec, 'text', BTRIM(best_conversation_raw)) ORDER BY ec)
          FILTER (WHERE NULLIF(BTRIM(best_conversation_raw), '') IS NOT NULL)
          AS best_conversations,
        SUM(previous_full_revenue) AS previous_full_revenue,
        SUM(previous_revenue) AS previous_revenue,
        SUM(current_revenue) AS current_revenue,
        SUM(previous_month_total) AS previous_month_total,
        SUM(current_month_total) AS current_month_total,
        MIN(previous_period) AS previous_period,
        MIN(current_period) AS current_period,
        MIN(max_known_day) AS max_known_day
      FROM (#{ec_listing_sql}) ecs
      GROUP BY channel_id, sub_channel_id, cnpj, company_uuid
      #{having_clause}
    SQL
  end

  # Um EC por linha, com os dois meses alinhados. É a base do agrupamento acima e não
  # carrega filtro nenhum da tela — quem filtra é o HAVING, pelo motivo explicado lá.
  def ec_listing_sql
    <<~SQL
      WITH #{AuditViews.latest_batches_sql(channel_predicate: "(:channel_id IS NULL OR ib.channel_id = :channel_id)").strip}
      SELECT snapshot.channel_id, snapshot.sub_channel_id, establishment.id AS establishment_id,
        establishment.uuid AS establishment_uuid,
        establishment.ec, company.cnpj, company.uuid AS company_uuid,
        note.id AS note_id, note.updated_at AS note_updated_at,
        snapshot.legal_name, snapshot.trade_name,
        snapshot.contract_status, mapa.accredited_on, mapa.activated_on,
        mapa.suspended_on, mapa.last_app_access_at, mapa.best_conversation_raw,
        mapa.has_payment_link, mapa.smart_pos_count, mapa.other_pos_count,
        mapa.tap_on_phone_count, mapa.mps_count, mapa.pin_count, mapa.tef_count,
        mapa.other_terminals_count, mapa.net_mdr, mapa.net_mdr_status,
        snapshot.previous_month_total, snapshot.current_month_total,
        -- Com cast: o literal sem tipo sobe para o MIN() da consulta de fora, que não
        -- consegue determinar o tipo de um unknown.
        :previous_period::date AS previous_period, :current_period::date AS current_period,
        :to_day::int AS max_known_day,
        #{AuditViews.aligned_aggregates_sql(
          table: "revenue", previous_period: ":previous_period", current_period: ":current_period",
          day_filter: "revenue.day BETWEEN :from_day AND :to_day"
        ).indent(4).strip}
      FROM revenue_snapshots snapshot
      JOIN latest_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      -- A anotação do cliente se liga pelo CNPJ, não por FK: id e uuid de companies são
      -- regenerados a cada recriação do banco. Aqui só vêm a existência e a data; o corpo é
      -- rich text e é carregado à parte.
      LEFT JOIN company_notes note ON note.cnpj = company.cnpj
      LEFT JOIN LATERAL (
        SELECT mapa.accredited_on, mapa.activated_on, mapa.suspended_on,
          mapa.last_app_access_at, mapa.best_conversation_raw,
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
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, establishment.id, establishment.ec,
        company.cnpj, company.uuid, note.id, note.updated_at,
        snapshot.legal_name, snapshot.trade_name, snapshot.contract_status,
        mapa.accredited_on, mapa.activated_on, mapa.suspended_on, mapa.last_app_access_at,
        mapa.best_conversation_raw, mapa.has_payment_link,
        mapa.smart_pos_count, mapa.other_pos_count, mapa.tap_on_phone_count, mapa.mps_count,
        mapa.pin_count, mapa.tef_count, mapa.other_terminals_count,
        mapa.net_mdr, mapa.net_mdr_status,
        snapshot.previous_month_total, snapshot.current_month_total
    SQL
  end

  def client_dates_select
    CLIENT_DATES.map { |name, expression| "#{expression} AS #{name}" }.join(",\n    ")
  end

  # Os filtros da tela nasceram por EC, mas a linha agora é o cliente — então eles agem
  # sobre a linha agrupada, no HAVING, e não no WHERE da consulta de dentro. A diferença
  # não é de estilo: num WHERE antes do GROUP BY, o cliente com três ECs em que só um casa
  # com o filtro apareceria com a soma de **um** EC. Faturamento errado e calado, numa tela
  # de auditoria. Aqui o filtro escolhe o cliente e a soma é sempre dos ECs todos.
  #
  # Status e data comparam o valor agregado, o mesmo que a linha mostra. A busca é a
  # exceção e compara EC por EC: quem digita o número de um EC está procurando o cliente
  # dono dele, e o EC não está mais na tela para ser comparado como agregado.
  def having_clause
    conditions = [ status_condition, lifecycle_condition, search_condition ].compact
    return "" if conditions.empty?

    "HAVING #{conditions.join(' AND ')}"
  end

  def status_condition
    "#{CLIENT_STATUS} IN (:statuses)" if @statuses.any?
  end

  def lifecycle_condition
    columns = active_date_kinds.filter_map { |kind| DATE_KINDS[kind] }
    return if columns.empty?

    expressions = columns.map do |column|
      "#{CLIENT_DATES.fetch(column)} BETWEEN :from_date AND :to_date"
    end
    "(#{expressions.join(' OR ')})"
  end

  # O termo alcança o texto da melhor conversa, e só ele passa por unaccent: os 418 textos
  # do lote mais recente têm acento, os 418, e sem isso quem digitasse "antecipacao" não
  # acharia nada. EC, CNPJ e nomes seguem com ILIKE puro — mudá-los mudaria o resultado de
  # uma busca que já existe.
  #
  # O bool_or é o que faz buscar por um EC devolver o cliente com a soma dos ECs dele, e
  # não aquele EC sozinho.
  def search_condition
    return if binds[:query].blank?

    <<~SQL.squish
      bool_or(
        ec ILIKE :query
        OR legal_name ILIKE :query
        OR trade_name ILIKE :query
        OR cnpj ILIKE :query
        OR unaccent(best_conversation_raw) ILIKE unaccent(:query)
        OR (
          :query_digits IS NOT NULL
          AND (cnpj ILIKE :query_digits OR ec ILIKE :query_digits)
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
