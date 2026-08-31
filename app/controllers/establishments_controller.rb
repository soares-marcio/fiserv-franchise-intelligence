class EstablishmentsController < ApplicationController
  PER_PAGE_OPTIONS = EstablishmentListingQuery::PER_PAGE_OPTIONS
  DEFAULT_PER_PAGE = EstablishmentListingQuery::DEFAULT_PER_PAGE

  # A busca ao vivo e a paginação pedem só o frame da listagem; acessada direto, a página
  # ganha a casca.
  layout -> { turbo_frame_request? ? false : "application" }

  # Uma linha por CNPJ: o cliente é a empresa; os ECs são o grão técnico e aparecem
  # agrupados. A busca continua por qualquer campo de qualquer EC da empresa.
  def index
    @query = params[:q].to_s.strip
    matching = @query.present? ? Establishment.search(@query) : Establishment.all
    companies = Company.joins(:establishments).where(establishments: { id: matching.select(:id) })
    @total_count = companies.distinct.count(:id)
    @total_establishments = matching.except(:includes).distinct.count(:id)
    @page, @per_page, @total_pages = paginate(@total_count)
    page_companies = companies.group("companies.id")
      .select("companies.*, MIN(establishments.ec) AS first_ec").order("first_ec")
      .offset((@page - 1) * @per_page).limit(@per_page)
    @establishments_by_company = Establishment.where(company_id: page_companies.map(&:id))
      .includes(:company, :channel, :primary_establishment, current_map_snapshot: :sub_channel)
      .order(:ec).group_by(&:company)
    @companies = page_companies.map { |company| @establishments_by_company.keys.find { |c| c.id == company.id } }
  end

  def show
    @establishment = Establishment.find_param!(params[:id])
    @snapshot = @establishment.current_map_snapshot
  end

  private

  # Mesmas regras da listagem por subcanal: tamanho dentro do teto, página dentro do total.
  def paginate(total_count)
    per_page = params[:per_page].to_i
    per_page = DEFAULT_PER_PAGE unless per_page.positive?
    per_page = PER_PAGE_OPTIONS.max if per_page > PER_PAGE_OPTIONS.max
    total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    page = [ [ params[:page].to_i, 1 ].max, total_pages ].min
    [ page, per_page, total_pages ]
  end

  def listing_params(overrides = {})
    { q: @query, per_page: @per_page, page: @page }.merge(overrides).compact_blank
  end
  helper_method :listing_params
end
