class EstablishmentsController < ApplicationController
  before_action :load_form_options, only: %i[new create]

  def index
    @query = params[:q].to_s.strip
    scope = Establishment.includes(
      :company, :channel, :primary_establishment, current_map_snapshot: :sub_channel
    )
    scope = filter_establishments(scope) if @query.present?
    @establishments = scope.order(:ec).limit(100)
  end

  def new
    @establishment = Establishment.new
  end

  def show
    @establishment = Establishment.find_param!(params[:id])
    @snapshot = @establishment.current_map_snapshot
  end

  def create
    @batch = Operations::RegisterManually.call(manual_params)
    establishment = @batch.map_snapshots.first.establishment
    redirect_to establishment, notice: "Cadastro manual gravado."
  rescue ArgumentError => error
    @establishment = Establishment.new
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  private

  def filter_establishments(scope)
    like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    scope.left_joins(:company, current_map_snapshot: :sub_channel).where(
      "establishments.ec ILIKE :q OR companies.cnpj ILIKE :q OR " \
      "map_snapshots.trade_name ILIKE :q OR map_snapshots.legal_name ILIKE :q OR " \
      "map_snapshots.city ILIKE :q OR map_snapshots.cnae_code ILIKE :q OR " \
      "map_snapshots.cnae_description ILIKE :q OR sub_channels.name ILIKE :q",
      q: like
    ).distinct
  end

  def load_form_options
    @channels = Channel.order(:name)
    @sub_channel_names = SubChannel.order(:name).pluck(:name).uniq
  end

  def manual_params
    params.require(:manual_entry).permit(
      :report_id, :channel_name, :sub_channel_name, :ec, :cnpj, :contract_status,
      :legal_name, :trade_name, :entity_type, :business_line,
      :cnae_code, :cnae_description, :street_address, :cep, :city, :state,
      :work_phone, :contact_name_1, :contact_name_2,
      :presumed_segment, :performed_segment,
      :previous_period, :current_period, :previous_month_total, :current_month_total,
      *(1..31).flat_map { |day| [ format("dia_%02d", day), format("dia_%02d_m1", day) ] }
    )
  end
end
