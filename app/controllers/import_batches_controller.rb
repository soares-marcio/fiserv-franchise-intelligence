class ImportBatchesController < ApplicationController
  def index
    @import_batches = ImportBatch.includes(:channel).order(created_at: :desc).limit(50)
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
  end

  def update_cutoff
    batch = ImportBatch.find_param!(params[:id])
    Operations::AdjustCutoff.call(batch:, max_dia_conhecido: params.require(:max_dia_conhecido))
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
