module Platform
  class SubChannelsController < ApplicationController
    def restore
      authorize :sub_channel, :restore?
      sub_channel = SubChannel.deleted.find_param!(params[:id])
      organization = sub_channel.channel.organization
      Operations::SoftDelete.restore_sub_channel(sub_channel:)
      Audit.record("sub_channel.restored", record: organization, request:,
        metadata: { report_id: sub_channel.channel.external_id })
      redirect_to platform_organization_path(organization), notice: "MIC restaurado."
    rescue ArgumentError => error
      redirect_to platform_organization_path(organization), alert: error.message
    end
  end
end
