# Listagem paginada de estabelecimentos de um subcanal, com os dois meses alinhados
# pela mesma faixa de dias. O resumo (contagem e totais) roda sem os agregados diários,
# que só a página precisa.
class EstablishmentListingQuery
  DATE_KINDS = {
    "credenciamento" => "mapa.accredited_on",
    "ativacao" => "mapa.activated_on",
    "suspensao" => "mapa.suspended_on"
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
      totals: { previous_full_revenue: 0.to_d, previous_revenue: 0.to_d, current_revenue: 0.to_d }
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
        COALESCE(SUM(previous_full_revenue), 0) AS previous_full_revenue,
        COALESCE(SUM(previous_revenue), 0) AS previous_revenue,
        COALESCE(SUM(current_revenue), 0) AS current_revenue
      FROM (#{listing_sql(include_days: false)}) listings
    SQL
    row = ApplicationRecord.connection.exec_query(sql).first || {}
    {
      total_count: row["total_count"].to_i,
      totals: {
        previous_full_revenue: row["previous_full_revenue"].to_d,
        previous_revenue: row["previous_revenue"].to_d,
        current_revenue: row["current_revenue"].to_d
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
        establishment.ec, company.cnpj, snapshot.legal_name, snapshot.trade_name,
        snapshot.contract_status, mapa.accredited_on, mapa.activated_on,
        mapa.suspended_on, snapshot.previous_month_total, snapshot.current_month_total,
        :previous_period AS previous_period, :current_period AS current_period,
        :to_day AS max_known_day,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = :previous_period
        ), 0) AS previous_full_revenue,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = :previous_period
            AND revenue.day BETWEEN :from_day AND :to_day
        ), 0) AS previous_revenue,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = :current_period
            AND revenue.day BETWEEN :from_day AND :to_day
        ), 0) AS current_revenue#{daily_columns(include_days)}
      FROM revenue_snapshots snapshot
      JOIN latest_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      LEFT JOIN LATERAL (
        SELECT mapa.accredited_on, mapa.activated_on, mapa.suspended_on
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
        mapa.accredited_on, mapa.activated_on, mapa.suspended_on, snapshot.previous_month_total,
        snapshot.current_month_total
    SQL
  end

  # Os lançamentos diários só interessam à página; o resumo não paga esse agregado.
  def daily_columns(include_days)
    return "" unless include_days

    <<~SQL.chomp
      ,
        COALESCE(jsonb_object_agg(revenue.day::text, revenue.amount) FILTER (
          WHERE revenue.period = :previous_period
        ), '{}'::jsonb) AS previous_days,
        COALESCE(jsonb_object_agg(revenue.day::text, revenue.amount) FILTER (
          WHERE revenue.period = :current_period
            AND revenue.day BETWEEN :from_day AND :to_day
        ), '{}'::jsonb) AS current_days
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
