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
    # Uma consulta para a página inteira, pelo CNPJ: a anotação não tem FK para companies.
    @notes_by_cnpj = CompanyNote.where(cnpj: @companies.map(&:cnpj)).index_by(&:cnpj)
  end

  # A ficha é do estabelecimento — o CNPJ —, e os ECs são os produtos contratados nele: POS,
  # Smart POS, link de pagamento. Medido na carteira: 173 dos 187 CNPJs com mais de um EC têm
  # equipamento diferente entre eles, então o equipamento é do EC e o cadastro é do cliente.
  def show
    @company = Company.find_by(uuid: params[:id])
    return redirect_to_company_of_establishment if @company.nil?

    @establishments = @company.establishments
      .includes(current_map_snapshot: :sub_channel).order(:ec)
    # A fonte dos campos do cliente é o EC de menor número, a mesma regra efetiva da listagem:
    # ficha e listagem precisam mostrar o mesmo nome e o mesmo endereço para o mesmo cliente.
    @snapshot = @establishments.first&.current_map_snapshot
    @diverging = diverging_client_fields(@establishments)
    # A anotação se liga pelo CNPJ, não por FK — ver o porquê no CLAUDE.md.
    @note = CompanyNote.with_rich_text_body.find_by(cnpj: @company.cnpj)
  end

  private

  # Link salvo aponta para o uuid do EC: em vez de 404, leva à ficha do cliente, ancorada no
  # bloco daquele EC.
  def redirect_to_company_of_establishment
    establishment = Establishment.find_param!(params[:id])
    redirect_to establishment_path(establishment.company, anchor: "ec-#{establishment.ec}")
  end

  # Campos do cliente que divergem entre os ECs. São poucos e reais — endereço em 13 dos 187
  # clientes com mais de um EC, razão social em 3, CNAE e MIC em 1 —, e a tela avisa em vez de
  # escolher em silêncio.
  CLIENT_FIELDS = %i[street_address city state cep cnae_code presumed_segment legal_name].freeze

  def diverging_client_fields(establishments)
    snapshots = establishments.filter_map(&:current_map_snapshot)
    return [] if snapshots.size < 2

    CLIENT_FIELDS.select { |field| snapshots.map { |snap| snap.public_send(field) }.uniq.size > 1 }
  end

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
