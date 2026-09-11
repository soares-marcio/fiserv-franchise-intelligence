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
    responder(company, note, notice: note ? "Anotação salva." : "Anotação removida.")
  rescue ArgumentError => error
    responder(company, CompanyNote.find_by(cnpj: company&.cnpj), alert: error.message)
  end

  private

  # Salvar não recarrega a tela: troca a célula daquele cliente e o aviso, e pronto. O id vem
  # do mesmo helper que a partial usa para escrevê-lo — é o que impede as duas pontas de
  # divergirem em silêncio.
  #
  # O caminho HTML fica de pé para quem chegar sem JavaScript, e é ele que os testes de
  # redirect exercitam.
  def responder(company, note, **flash_message)
    respond_to do |format|
      format.turbo_stream do
        flash.now[flash_message.keys.first] = flash_message.values.first
        render turbo_stream: [
          turbo_stream.replace(
            helpers.company_note_cell_id(company.uuid),
            partial: "shared/company_note_cell", locals: celula(company, note)
          ),
          turbo_stream.update("flash", partial: "layouts/flash",
            locals: { notice: flash.now[:notice], alert: flash.now[:alert] })
        ]
      end
      format.html { redirect_to origin_path, **flash_message }
    end
  end

  def celula(company, note)
    {
      company_uuid: company.uuid,
      name: company.establishments.first&.current_map_snapshot&.trade_name.to_s,
      note_id: note&.id, note_updated_at: note&.updated_at,
      note_params: params[:origin] == "sub_channel" ? origin_params : {}
    }
  end

  # O botão trocado precisa continuar levando o recorte da tela junto, senão a próxima
  # abertura perde o filtro que a primeira tinha.
  def origin_params
    listing_params.merge(origin: "sub_channel", sub_channel_id: params[:sub_channel_id])
  end

  # A rota da anotação usa a uuid, não o CNPJ. O filter_parameter_logging já esconde :cnpj dos
  # logs, mas ele filtra parâmetros e não o caminho da URL — um /companies/<cnpj>/note
  # gravaria CNPJ em toda linha de log de acesso.
  def origin_path
    sub_channel = params[:sub_channel_id].presence
    if params[:origin] == "sub_channel" && sub_channel
      return sub_channel_report_path(sub_channel, listing_params)
    end

    # Origem desconhecida, ausente ou sem o MIC cai no Clover Capital: lá a linha é o próprio
    # cliente, então quem salvou vê a anotação que acabou de escrever. O recorte da tela vai
    # junto, senão salvar desfaz o filtro de quem chegou filtrando.
    stalled_reports_path(channel_id: params[:channel_id].presence,
      sub_channel_id: params[:sub_channel_id].presence)
  end

  def listing_params
    params.slice(*LISTING_PARAM_KEYS).permit!.to_h.symbolize_keys.compact_blank
  end
end
