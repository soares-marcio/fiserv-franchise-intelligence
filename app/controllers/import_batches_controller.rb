class ImportBatchesController < ApplicationController
  # Todo .xlsx é um ZIP: a assinatura barra um arquivo renomeado antes de o parse abri-lo.
  XLSX_SIGNATURE = "PK\x03\x04".b

  rate_limit to: 5, within: 1.minute, only: :create,
    with: -> { redirect_to import_batches_path, alert: "Muitos envios em sequência. Aguarde um minuto." }

  def index
    @import_batches = ImportBatch.includes(:channel).order(created_at: :desc).limit(50)
    @days_since_last_file = ImportBatch.days_since_last_file
    @running_batch = @import_batches.find(&:running?)
    @stuck_batches = @import_batches.select(&:stuck?)
    @last_batch = @import_batches.first
    @worker_alive = ImportBatch.worker_alive?
    @worker_heartbeat_at = ImportBatch.worker_heartbeat_at
  end

  def show
    @import_batch = ImportBatch.find_param!(params[:id])
  end

  def create
    upload = params.require(:file)
    if (alert = upload_rejection(upload))
      redirect_to import_batches_path, alert: alert
      return
    end

    Operations::ImportFile.call(upload)
    redirect_to import_batches_path, notice: "Importação enfileirada."
  rescue ActionController::ParameterMissing
    redirect_to import_batches_path, alert: "Selecione um arquivo."
  rescue ArgumentError => error
    redirect_to import_batches_path, alert: error.message
  end

  def destroy
    batch = ImportBatch.find_param!(params[:id])
    unless batch.discardable?
      redirect_to import_batch_path(batch), alert: "Só lotes que falharam antes de gravar dados podem ser descartados."
      return
    end

    batch.destroy!
    redirect_to import_batches_path, notice: "Lote descartado."
  end

  def update_cutoff
    batch = ImportBatch.find_param!(params[:id])
    Operations::AdjustCutoff.call(batch:, max_known_day: params.require(:max_known_day))
    redirect_to import_batch_path(batch), notice: "Dia de corte atualizado."
  rescue ArgumentError => error
    redirect_to import_batch_path(params[:id]), alert: error.message
  end

  def reprocess
    batch = ImportBatch.find_param!(params[:id])
    Operations::ReprocessBatch.call(batch)
    redirect_to import_batch_path(batch), notice: "Lote reprocessado."
  rescue ArgumentError => error
    redirect_to import_batch_path(params[:id]), alert: error.message
  end

  private

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
