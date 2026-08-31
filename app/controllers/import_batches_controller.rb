class ImportBatchesController < ApplicationController
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
    unless File.extname(upload.original_filename.to_s).casecmp(".xlsx").zero?
      redirect_to import_batches_path, alert: "Envie um arquivo .xlsx."
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
end
