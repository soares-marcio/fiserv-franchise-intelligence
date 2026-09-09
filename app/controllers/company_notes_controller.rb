# Anotação do cliente. Duas telas a editam — a listagem do MIC e o Clover Capital — e cada uma
# volta para o próprio recorte.
#
# A tela de origem chega declarada na requisição, e o destino é montado aqui por route helper,
# a partir de uma lista fechada. Caminho que venha na requisição nunca é seguido: seria
# redirecionamento aberto, e o projeto entrega com o brakeman limpo, sem baseline de ignore.
# O que a requisição escolhe é qual das telas conhecidas, não para onde.
class CompanyNotesController < ApplicationController
  # Os mesmos parâmetros que ReportsController#sub_channel_listing_params carrega na URL.
  # Voltar sem eles jogaria quem anotou na página 3, filtrada, de volta na primeira página
  # sem filtro.
  LISTING_PARAM_KEYS = %i[
    channel_id variation status date_kind from_date to_date q sort direction
    period from_day to_day per_page page
  ].freeze

  # Conteúdo do modal, carregado sob demanda. Diferente dos outros modais do projeto, este
  # não pode viajar num data-* do botão: o corpo é HTML com anexos, e vinte linhas de tabela
  # carregariam vinte deles. Chega por Turbo Frame, como o modal do calendário.
  layout -> { turbo_frame_request? ? false : "application" }

  def edit
    @company = Company.find_param!(params[:id])
    @note = CompanyNote.find_or_initialize_by(cnpj: @company.cnpj)
    @snapshot = MapSnapshot.joins(:establishment)
      .where(establishments: { company_id: @company.id })
      .order(id: :desc).first
  end

  def update
    company = Company.find_param!(params[:id])
    note = Operations::SaveCompanyNote.call(cnpj: company.cnpj, body: params[:body])
    redirect_to origin_path, notice: note ? "Anotação salva." : "Anotação removida."
  rescue ArgumentError => error
    redirect_to origin_path, alert: error.message
  end

  private

  # A rota da anotação usa a uuid, não o CNPJ. O filter_parameter_logging já esconde :cnpj dos
  # logs, mas ele filtra parâmetros e não o caminho da URL — um /companies/<cnpj>/note
  # gravaria CNPJ em toda linha de log de acesso.
  def origin_path
    sub_channel = params[:sub_channel_id].presence
    if params[:origin] == "sub_channel" && sub_channel
      return sub_channel_report_path(sub_channel, listing_params)
    end

    # Origem desconhecida, ausente ou sem o MIC cai no Clover Capital: lá a linha é o próprio
    # cliente, então quem salvou vê a anotação que acabou de escrever.
    stalled_reports_path(channel_id: params[:channel_id].presence)
  end

  def listing_params
    params.slice(*LISTING_PARAM_KEYS).permit!.to_h.symbolize_keys.compact_blank
  end
end
