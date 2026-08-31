class EstablishmentsController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    scope = Establishment.includes(
      :company, :channel, :primary_establishment, current_map_snapshot: :sub_channel
    )
    scope = scope.search(@query) if @query.present?
    @establishments = scope.order(:ec).limit(100)
  end

  def show
    @establishment = Establishment.find_param!(params[:id])
    @snapshot = @establishment.current_map_snapshot
  end
end
