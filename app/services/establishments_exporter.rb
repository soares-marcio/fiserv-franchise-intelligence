# Exportação do cadastro corrente: uma linha por cliente, com os ECs dele numa célula. Leva a
# busca da tela e larga a paginação — o arquivo é do filtro, não da página que estava à vista.
class EstablishmentsExporter
  HEADERS = [
    "CNPJ", "Razão social", "Nome fantasia", "ECs", "Quantidade de ECs", "MIC", "Master",
    "Endereço", "Cidade", "UF", "CEP", "CNAE", "Descrição do CNAE", "Status do contrato",
    "Segmento performado", "Ramo de atividade"
  ].freeze

  def initialize(companies, establishments_by_company:, query: nil)
    @companies = companies
    @establishments_by_company = establishments_by_company
    @query = query
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers: HEADERS, rows: @companies.map { |company| export_row(company) },
      sheet_name: "Estabelecimentos", note:)
  end

  def note
    return "Cadastro corrente do Mapa de Clientes BIN" if @query.blank?

    "Cadastro corrente do Mapa de Clientes BIN · busca: #{@query}"
  end

  def export_row(company)
    establishments = @establishments_by_company.fetch(company, [])
    # O EC de referência é o mesmo da tela: o que não é duplicata de outro; entre vários, o
    # menor. Cadastro que diverge entre ECs sai pelo de referência, como a linha mostra.
    lead = establishments.find { |e| e.primary_establishment.nil? } || establishments.first
    snapshot = lead&.current_map_snapshot
    [
      helpers.formatted_cnpj(company.cnpj), snapshot&.legal_name, snapshot&.trade_name,
      establishments.map(&:ec).join(" · "), establishments.size,
      mics(establishments), helpers.channel_name(lead&.channel),
      snapshot&.street_address, snapshot&.city, snapshot&.state, helpers.formatted_cep(snapshot&.cep),
      snapshot&.cnae_code, snapshot&.cnae_description,
      helpers.contract_status_label(snapshot&.contract_status),
      snapshot&.performed_segment, snapshot&.business_line
    ]
  end

  # Um CNPJ pode ter ECs em MICs diferentes, e a tela os lista todos: o arquivo faz igual.
  def mics(establishments)
    establishments.filter_map { |e| e.current_map_snapshot&.sub_channel&.name }.uniq.join(" · ")
  end

  def helpers = ApplicationController.helpers
end
