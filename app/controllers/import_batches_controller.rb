class ImportBatchesController < ApplicationController
  # Todo .xlsx é um ZIP: a assinatura barra um arquivo renomeado antes de o parse abri-lo.
  XLSX_SIGNATURE = "PK\x03\x04".b

  rate_limit to: 5, within: 1.minute, only: :create,
    with: -> { redirect_to import_batches_path, alert: "Muitos envios em sequência. Aguarde um minuto." }

  # Uma chave por ação: ver o histórico, enviar arquivo, mexer num lote e descartá-lo são
  # decisões diferentes, e quem concede acesso decide cada uma. As ações sobre um lote
  # específico autorizam o próprio registro, porque a regra também pergunta de quem ele é.
  before_action :load_batch, only: %i[show destroy update_cutoff reprocess review approve reject]
  before_action -> { authorize(@import_batch || :import_batch, "#{action_name}?".to_sym) }

  def index
    @import_batches = policy_scope(ImportBatch).includes(:channel).order(created_at: :desc).limit(50)
    @days_since_last_file = ImportBatch.days_since_last_file(organization: Current.organization)
    @running_batch = @import_batches.find(&:running?)
    @stuck_batches = @import_batches.select(&:stuck?)
    @last_batch = @import_batches.first
    @worker_alive = ImportBatch.worker_alive?
    @worker_heartbeat_at = ImportBatch.worker_heartbeat_at
  end

  def show
    return unless policy(@import_batch).grant?

    @grants = BatchGrant.where(import_batch: @import_batch).includes(:user).order("users.name")
    # Elegíveis: quem este ator administra, ainda não tem o arquivo e tem o Master inteiro.
    # Super admin já vê tudo; quem enviou também.
    fora = @grants.map(&:user_id) + [ Current.user.id, @import_batch.uploaded_by_id ].compact
    @eligible = policy_scope(User).active.where(platform_admin: false, organization_admin: false)
      .where.not(id: fora).order(:name)
      .select { |candidate| AccessScope.for(candidate).whole?(@import_batch.channel_id) }
  end

  def create
    upload = params.require(:file)
    if (alert = upload_rejection(upload))
      redirect_to import_batches_path, alert: alert
      return
    end

    batch = Operations::ImportFile.call(upload, uploaded_by: Current.user)
    Audit.record("batch.uploaded", record: batch, request:,
      metadata: { arquivo: upload.original_filename })
    redirect_to import_batches_path, notice: "Importação enfileirada."
  rescue ActionController::ParameterMissing
    redirect_to import_batches_path, alert: "Selecione um arquivo."
  rescue ArgumentError => error
    redirect_to import_batches_path, alert: error.message
  end

  def destroy
    batch = @import_batch
    unless batch.discardable?
      redirect_to import_batch_path(batch), alert: "Só lotes que falharam antes de gravar dados podem ser descartados."
      return
    end

    Audit.record("batch.discarded", record: batch, request:,
      metadata: { arquivo: batch.source_filename })
    batch.destroy!
    redirect_to import_batches_path, notice: "Lote descartado."
  end

  def update_cutoff
    batch = @import_batch
    Operations::AdjustCutoff.call(batch:, max_known_day: params.require(:max_known_day))
    redirect_to import_batch_path(batch), notice: "Dia de corte atualizado."
  rescue ArgumentError => error
    redirect_to import_batch_path(params[:id]), alert: error.message
  end

  # A tela que mostra o que muda se este lote passar a valer.
  def review
    @review = BatchReview.new(@import_batch)
  end

  def approve
    Operations::ReviewBatch.approve(batch: @import_batch, reviewer: Current.user,
      note: params[:review_note])
    redirect_to import_batch_path(@import_batch), notice: "Lote aprovado e consolidado."
  rescue ArgumentError => error
    redirect_to review_import_batch_path(@import_batch), alert: error.message
  end

  def reject
    Operations::ReviewBatch.reject(batch: @import_batch, reviewer: Current.user,
      note: params[:review_note])
    redirect_to import_batch_path(@import_batch), notice: "Lote recusado."
  rescue ArgumentError => error
    redirect_to review_import_batch_path(@import_batch), alert: error.message
  end

  def reprocess
    batch = @import_batch
    Operations::ReprocessBatch.call(batch)
    redirect_to import_batch_path(batch), notice: "Lote reprocessado."
  rescue ArgumentError => error
    redirect_to import_batch_path(params[:id]), alert: error.message
  end

  private

  # Fora do alcance do ator, o lote responde 404 — não 403: dizer "existe, mas não é seu"
  # conta que aquele arquivo foi enviado, e por alguém.
  def load_batch
    @import_batch = policy_scope(ImportBatch).find_param!(params[:id])
  end

  def upload_rejection(upload)
    extensao = File.extname(upload.original_filename.to_s)
    unless extensao.casecmp(".xlsx").zero?
      return "O arquivo precisa ser .xlsx e este é #{extensao.presence || 'sem extensão'}. " \
        "Se a planilha estiver em .xls ou .csv, abra no Excel e salve como .xlsx."
    end
    if upload.size > Operations::ImportFile::MAX_UPLOAD_BYTES
      limite = Operations::ImportFile::MAX_UPLOAD_BYTES / 1.megabyte
      return "O arquivo tem #{ActiveSupport::NumberHelper.number_to_human_size(upload.size)} " \
        "e o limite é #{limite} MB. " \
        "A planilha BIN costuma ter menos de 1 MB: confira se não foi enviado outro arquivo."
    end

    unless xlsx_signature?(upload)
      "O arquivo tem extensão .xlsx mas o conteúdo não é de uma planilha. Isso acontece " \
        "quando um .csv ou .xls é renomeado à mão: abra no Excel e salve como .xlsx."
    end
  end

  def xlsx_signature?(upload)
    upload.rewind
    upload.read(XLSX_SIGNATURE.bytesize) == XLSX_SIGNATURE
  ensure
    upload.rewind
  end
end
