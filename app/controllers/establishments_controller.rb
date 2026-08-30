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
      "map_snapshots.nome_fantasia ILIKE :q OR map_snapshots.razao_social ILIKE :q OR " \
      "map_snapshots.cidade ILIKE :q OR map_snapshots.cnae_codigo ILIKE :q OR " \
      "map_snapshots.cnae_descricao ILIKE :q OR sub_channels.sub_canal ILIKE :q",
      q: like
    ).distinct
  end

  def load_form_options
    @channels = Channel.order(:canal)
    @sub_canals = SubChannel.order(:sub_canal).pluck(:sub_canal).uniq
  end

  def manual_params
    params.require(:manual_entry).permit(
      :report_id, :canal, :sub_canal, :ec, :cnpj, :status_contrato,
      :razao_social, :nome_fantasia, :tipo_pessoa, :ramo_atividade,
      :cnae_codigo, :cnae_descricao, :endereco, :cep, :cidade, :estado,
      :telefone_trabalho, :nome_contato_1, :nome_contato_2,
      :segmento_presumido, :segmento_performado,
      :competencia_m1, :competencia_atual, :fat_total_m1, :fat_total_mes_atual,
      *(1..31).flat_map { |day| [ format("dia_%02d", day), format("dia_%02d_m1", day) ] }
    )
  end
end
