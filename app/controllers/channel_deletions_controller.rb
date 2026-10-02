# A tela que apaga um Master da organização. Mostra o que some e o que fica, e só apaga com
# o nome digitado — a checagem é do servidor, não do botão.
class ChannelDeletionsController < ApplicationController
  before_action :load_channel

  def new
    @counts = Operations::SoftDelete.channel_counts(@channel)
  end

  def create
    counts = Operations::SoftDelete.delete_channel(channel: @channel, actor: Current.user,
      confirmation: params[:confirmation])
    Audit.record("channel.deleted", record: @channel, channel: @channel, request:,
      metadata: counts.merge("master" => @channel.name, "report_id" => @channel.external_id))
    redirect_to import_batches_path,
      notice: "Master #{@channel.name} apagado. Os dados ficam guardados; só a plataforma restaura."
  rescue ArgumentError => error
    @counts = Operations::SoftDelete.channel_counts(@channel)
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  private

  # Primeiro a regra (403 para quem não administra a organização), depois a busca dentro da
  # própria organização: Master de outra responde 404, sem dizer que existe.
  def load_channel
    authorize :channel, :destroy?
    @channel = Channel.active.where(organization_id: Current.organization&.id).find_param!(params[:channel_id])
    authorize @channel, :destroy?
  end
end
