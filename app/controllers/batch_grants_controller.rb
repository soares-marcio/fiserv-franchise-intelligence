# Liberação nominal de um arquivo importado: quem administra acessos e alcança o lote
# escolhe quem mais o vê. A regra de quem pode receber (Master inteiro) vive no modelo.
class BatchGrantsController < ApplicationController
  before_action :load_batch

  def create
    authorize @import_batch, :grant?
    recipient = policy_scope(User).find_param!(params[:user_id])
    BatchGrant.create!(user: recipient, import_batch: @import_batch, created_by: Current.user)
    Audit.record("batch.granted", record: @import_batch, request:,
      metadata: { arquivo: @import_batch.source_filename, alvo: recipient.email_address })
    redirect_to import_batch_path(@import_batch), notice: "Arquivo liberado para #{recipient.name}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to import_batch_path(@import_batch), alert: error.record.errors.full_messages.join("; ")
  end

  def destroy
    authorize @import_batch, :revoke?
    grant = BatchGrant.where(import_batch: @import_batch).find(params[:id])
    grant.destroy!
    Audit.record("batch.revoked", record: @import_batch, request:,
      metadata: { arquivo: @import_batch.source_filename, alvo: grant.user.email_address })
    redirect_to import_batch_path(@import_batch), notice: "Liberação revogada."
  end

  private

  # Fora do alcance, 404 — como em toda tela de lote.
  def load_batch
    @import_batch = policy_scope(ImportBatch).find_param!(params[:import_batch_id])
  end
end
