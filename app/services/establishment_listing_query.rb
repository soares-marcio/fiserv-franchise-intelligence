# Listagem paginada de estabelecimentos de um subcanal, com os dois meses alinhados
# pela mesma faixa de dias. O resumo (contagem e totais) roda sem os agregados diários,
# que só a página precisa.
class EstablishmentListingQuery
  DATE_KINDS = {
    "credenciamento" => "mapa.data_credenciamento",
    "ativacao" => "mapa.data_ativacao",
    "suspensao" => "mapa.data_suspensao"
  }.freeze
  PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
  DEFAULT_PER_PAGE = 20
  MIN_DIGITS_SEARCH = 3

  def initialize(channel_id:, sub_channel_id:, window:, statuses: [], date_kinds: [],
    from_date: nil, to_date: nil, query: nil, page: 1, per_page: nil)
    @channel_id = channel_id
    @sub_channel_id = sub_channel_id
    @window = window
    @statuses = Array(statuses).map(&:to_s).compact_blank.uniq
    @date_kinds = Array(date_kinds).map(&:to_s) & DATE_KINDS.keys
    @from_date = parse_date(from_date)
    @to_date = parse_date(to_date)
    @from_date, @to_date = @to_date, @from_date if inverted_range?
    @query = query.to_s.strip
    @page = page
    @per_page = per_page
  end

  def self.empty_page
    EstablishmentRevenuePage.new(
      rows: [], total_count: 0, page: 1, per_page: DEFAULT_PER_PAGE,
      totals: { faturamento_m1_cheio: 0.to_d, faturamento_m1: 0.to_d, faturamento_atual: 0.to_d }
    )
  end

  def call
    summary = fetch_summary
    page, per_page = normalize_page(summary[:total_count])

    EstablishmentRevenuePage.new(
      rows: fetch_rows(page, per_page), total_count: summary[:total_count],
      totals: summary[:totals], page:, per_page:
    )
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

    digits = @query.gsub(/\D/, "")
    digits = nil if digits.length < MIN_DIGITS_SEARCH
    {
      query: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%",
      query_digits: digits && "%#{ActiveRecord::Base.sanitize_sql_like(digits)}%"
    }
  end

  def fetch_summary
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      SELECT COUNT(*) AS total_count,
        COALESCE(SUM(faturamento_m1_cheio), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(faturamento_m1), 0) AS faturamento_m1,
        COALESCE(SUM(faturamento_atual), 0) AS faturamento_atual
      FROM (#{listing_sql(include_days: false)}) listings
    SQL
    row = ApplicationRecord.connection.exec_query(sql).first || {}
    {
      total_count: row["total_count"].to_i,
      totals: {
        faturamento_m1_cheio: row["faturamento_m1_cheio"].to_d,
        faturamento_m1: row["faturamento_m1"].to_d,
        faturamento_atual: row["faturamento_atual"].to_d
      }
    }
  end

  def fetch_rows(page, per_page)
    sql = ApplicationRecord.sanitize_sql_array([
      "#{listing_sql} ORDER BY ec, establishment_id LIMIT :per_page OFFSET :offset",
      binds.merge(per_page:, offset: (page - 1) * per_page)
    ])
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def normalize_page(total_count)
    size = @per_page.to_i
    size = DEFAULT_PER_PAGE unless size.positive?
    size = PER_PAGE_OPTIONS.max if size > PER_PAGE_OPTIONS.max
    total_pages = [ (total_count.to_f / size).ceil, 1 ].max
    [ [ [ @page.to_i, 1 ].max, total_pages ].min, size ]
  end

  def listing_sql(include_days: true)
    <<~SQL
      WITH latest_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND (:channel_id IS NULL OR ib.channel_id = :channel_id)
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots snapshot WHERE snapshot.import_batch_id = ib.id
          )
        GROUP BY ib.channel_id
      )
      SELECT snapshot.channel_id, snapshot.sub_channel_id, establishment.id AS establishment_id,
        establishment.ec, company.cnpj, snapshot.razao_social, snapshot.nome_fantasia,
        snapshot.status_contrato, mapa.data_credenciamento, mapa.data_ativacao,
        mapa.data_suspensao, snapshot.fat_total_m1, snapshot.fat_total_mes_atual,
        :competencia_m1 AS competencia_m1, :competencia_atual AS competencia_atual,
        :to_day AS max_dia_conhecido,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = :competencia_m1
        ), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = :competencia_m1
            AND revenue.day BETWEEN :from_day AND :to_day
        ), 0) AS faturamento_m1,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = :competencia_atual
            AND revenue.day BETWEEN :from_day AND :to_day
        ), 0) AS faturamento_atual#{daily_columns(include_days)}
      FROM revenue_snapshots snapshot
      JOIN latest_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      LEFT JOIN LATERAL (
        SELECT mapa.data_credenciamento, mapa.data_ativacao, mapa.data_suspensao
        FROM map_snapshots mapa
        WHERE mapa.establishment_id = establishment.id
          AND mapa.import_batch_id = snapshot.import_batch_id
        ORDER BY mapa.id DESC
        LIMIT 1
      ) mapa ON true
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = snapshot.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.competencia IN (:competencia_m1, :competencia_atual)
      WHERE snapshot.sub_channel_id = :sub_channel_id
        #{status_clause}
        #{lifecycle_clause}
        #{search_clause}
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, establishment.id, establishment.ec,
        company.cnpj, snapshot.razao_social, snapshot.nome_fantasia, snapshot.status_contrato,
        mapa.data_credenciamento, mapa.data_ativacao, mapa.data_suspensao, snapshot.fat_total_m1,
        snapshot.fat_total_mes_atual
    SQL
  end

  # Os lançamentos diários só interessam à página; o resumo não paga esse agregado.
  def daily_columns(include_days)
    return "" unless include_days

    <<~SQL.chomp
      ,
        COALESCE(jsonb_object_agg(revenue.day::text, revenue.amount) FILTER (
          WHERE revenue.competencia = :competencia_m1
        ), '{}'::jsonb) AS dias_m1,
        COALESCE(jsonb_object_agg(revenue.day::text, revenue.amount) FILTER (
          WHERE revenue.competencia = :competencia_atual
            AND revenue.day BETWEEN :from_day AND :to_day
        ), '{}'::jsonb) AS dias_atual
    SQL
  end

  def status_clause
    @statuses.any? ? "AND snapshot.status_contrato IN (:statuses)" : ""
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
        OR snapshot.razao_social ILIKE :query
        OR snapshot.nome_fantasia ILIKE :query
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
