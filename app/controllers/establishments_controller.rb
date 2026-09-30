class EstablishmentsController < ApplicationController
  PER_PAGE_OPTIONS = EstablishmentListingQuery::PER_PAGE_OPTIONS
  DEFAULT_PER_PAGE = EstablishmentListingQuery::DEFAULT_PER_PAGE

  # A busca ao vivo e a paginação pedem só o frame da listagem; acessada direto, a página
  # ganha a casca.
  layout -> { turbo_frame_request? ? false : "application" }
  before_action -> { authorize :establishment, :index? }

  # Uma linha por CNPJ: o cliente é a empresa; os ECs são o grão técnico e aparecem
  # agrupados. A busca continua por qualquer campo de qualquer EC da empresa.
  def index
    @query = params[:q].to_s.strip
    no_escopo = Establishment.in_scope(Current.access_scope)
    matching = @query.present? ? no_escopo.merge(Establishment.search(@query)) : no_escopo
    companies = Company.joins(:establishments).where(establishments: { id: matching.select(:id) })
    @total_count = companies.distinct.count(:id)
    @total_establishments = matching.except(:includes).distinct.count(:id)
    @page, @per_page, @total_pages = paginate(@total_count)
    page_companies = companies.group("companies.id")
      .select("companies.*, MIN(establishments.ec) AS first_ec").order("first_ec")
      .offset((@page - 1) * @per_page).limit(@per_page)
    # Só os ECs do escopo, também aqui: um CNPJ pode ter ECs em outro Master — ou em outra
    # organização —, e a listagem não pode mostrar de quem são.
    @establishments_by_company = Establishment.where(company_id: page_companies.map(&:id))
      .merge(Establishment.in_scope(Current.access_scope))
      .includes(:company, :channel, :primary_establishment, current_map_snapshot: :sub_channel)
      .order(:ec).group_by(&:company)
    @companies = page_companies.map { |company| @establishments_by_company.keys.find { |c| c.id == company.id } }
    # Uma consulta para a página inteira, pelo CNPJ: a anotação não tem FK para companies.
    @notes_by_cnpj = policy_scope(CompanyNote).where(cnpj: @companies.map(&:cnpj)).index_by(&:cnpj)
    respond_to do |format|
      format.html
      format.csv { send_data exporter(companies).to_csv, **arquivo("csv") }
      format.xlsx { send_data exporter(companies).to_xlsx, **arquivo("xlsx") }
    end
  end

  # A ficha é do estabelecimento — o CNPJ —, e os ECs são os produtos contratados nele: POS,
  # Smart POS, link de pagamento. Medido na carteira: 173 dos 187 CNPJs com mais de um EC têm
  # equipamento diferente entre eles, então o equipamento é do EC e o cadastro é do cliente.
  def show
    @company = companies_in_scope.find_by(uuid: params[:id])
    return redirect_to_company_of_establishment if @company.nil?

    # Só os ECs do escopo: um CNPJ pode ter ECs em mais de um Master, e a ficha não pode
    # misturar o que é de um com o que é de outro.
    @establishments = @company.establishments.in_scope(Current.access_scope)
      .includes(current_map_snapshot: :sub_channel).order(:ec)
    # A fonte dos campos do cliente é o EC de menor número, a mesma regra efetiva da listagem:
    # ficha e listagem precisam mostrar o mesmo nome e o mesmo endereço para o mesmo cliente.
    @snapshot = @establishments.first&.current_map_snapshot
    @diverging = diverging_client_fields(@establishments)
    # A anotação se liga pelo CNPJ, não por FK — ver o porquê no CLAUDE.md.
    @note = policy_scope(CompanyNote).with_rich_text_body.find_by(cnpj: @company.cnpj)
  end

  private

  # Empresas alcançáveis: as que têm ao menos um EC no escopo do ator.
  def companies_in_scope
    Company.where(id: Establishment.in_scope(Current.access_scope).select(:company_id))
  end

  # Link salvo aponta para o uuid do EC: em vez de 404, leva à ficha do cliente, ancorada no
  # bloco daquele EC.
  # EC fora do escopo responde 404 em vez de redirecionar: o redirecionamento confirmaria
  # que aquele EC existe, e para qual cliente ele aponta.
  def redirect_to_company_of_establishment
    establishment = Establishment.in_scope(Current.access_scope).find_param!(params[:id])
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
  # O arquivo é do filtro, não da página: a exportação refaz a consulta sem o recorte de
  # paginação. Exportar só a página entregaria um recorte que ninguém pediu.
  def exporter(companies)
    todas = companies.group("companies.id").select("companies.*, MIN(establishments.ec) AS first_ec")
      .order("first_ec").to_a
    por_empresa = Establishment.where(company_id: todas.map(&:id))
      .includes(:company, :channel, :primary_establishment, current_map_snapshot: :sub_channel)
      .order(:ec).group_by(&:company)
    # group_by devolve as instâncias carregadas aqui; a lista ordenada vem da outra consulta,
    # então as chaves precisam ser as mesmas instâncias para o fetch do exportador achá-las.
    ordenadas = todas.map { |company| por_empresa.keys.find { |c| c.id == company.id } }.compact
    EstablishmentsExporter.new(ordenadas, establishments_by_company: por_empresa, query: @query)
  end

  def arquivo(extensao)
    tipo = extensao == "csv" ? "text/csv" : Mime[:xlsx]
    nome = @query.present? ? "estabelecimentos-#{@query.parameterize}" : "estabelecimentos"
    { filename: "#{nome}.#{extensao}", type: tipo }
  end

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
