# A tela que apaga um MIC. O MIC some das telas e dos totais do Master; os ECs dele
# continuam no Master e voltam a aparecer quando uma planilha nova os ligar a um MIC ativo.
class SubChannelDeletionsController < ApplicationController
  before_action :load_sub_channel

  def new
    @establishments_count = Operations::SoftDelete.current_establishments(@sub_channel).count
  end

  def create
    counts = Operations::SoftDelete.delete_sub_channel(sub_channel: @sub_channel, actor: Current.user,
      confirmation: params[:confirmation])
    Audit.record("sub_channel.deleted", record: @sub_channel, channel: @sub_channel.channel, request:,
      metadata: counts.merge("mic" => @sub_channel.name))
    redirect_to reports_path, notice: "#{@sub_channel.name} apagado. Só a plataforma restaura."
  rescue ArgumentError => error
    @establishments_count = Operations::SoftDelete.current_establishments(@sub_channel).count
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  private

  def load_sub_channel
    authorize :sub_channel, :destroy?
    @sub_channel = SubChannel.active.joins(:channel).merge(Channel.active)
      .where(channels: { organization_id: Current.organization&.id }).find_param!(params[:sub_channel_id])
    authorize @sub_channel, :destroy?
  end
end
