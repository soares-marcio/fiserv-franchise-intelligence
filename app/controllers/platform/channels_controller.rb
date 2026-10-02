module Platform
  # Só a plataforma restaura Master apagado. A restauração é tudo ou nada e recusa quando
  # uma planilha nova já ocupou o REPORT_ID, um EC ou o arquivo.
  class ChannelsController < ApplicationController
    def restore
      authorize :channel, :restore?
      channel = Channel.deleted.find_param!(params[:id])
      Operations::SoftDelete.restore_channel(channel:)
      Audit.record("channel.restored", record: channel.organization, request:,
        metadata: { report_id: channel.external_id })
      redirect_to platform_organization_path(channel.organization), notice: "Master restaurado."
    rescue ArgumentError => error
      redirect_to platform_organization_path(channel.organization), alert: error.message
    end
  end
end
