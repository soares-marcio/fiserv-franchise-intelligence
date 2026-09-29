class UsersController < ApplicationController
  before_action :load_user, only: %i[show edit update reset_mfa deactivate reactivate]

  def index
    authorize :user, :index?
    @users = policy_scope(User).includes(:access_grants).order(:name)
  end

  def new
    authorize :user, :create?
    @user = User.new
    load_options
  end

  def create
    authorize :user, :create?
    @user = Operations::SaveUser.create(attributes: user_attributes, permissions: params[:permissions],
      grants: grant_params, actor: Current.user)
    # A senha provisória é de quem convidou entregar pessoalmente — não há e-mail configurado
    # no portal, e mandá-la por outro canal é decisão de quem convida, não do sistema. Ela
    # fica na listagem até a pessoa trocá-la; o flash some em segundos.
    flash[:notice] = "Usuário criado. Senha provisória: #{@senha_provisoria} — fica na listagem até a troca."
    redirect_to users_path
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record
    load_options
    render :new, status: :unprocessable_entity
  end

  def show
    authorize @user, :show?
    @grants = @user.access_grants.includes(:channel, :sub_channel)
    @batch_grants = @user.batch_grants.includes(import_batch: :channel)
  end

  def edit
    authorize @user, :update?
    load_options
  end

  def update
    authorize @user, :update?
    Operations::SaveUser.update(user: @user, attributes: user_attributes.except(:password),
      permissions: params[:permissions], grants: grant_params, actor: Current.user)
    redirect_to user_path(@user), notice: "Acesso atualizado."
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record
    load_options
    render :edit, status: :unprocessable_entity
  end

  # Perder o celular é o caso comum; reiniciar zera o segredo e os códigos, e a pessoa
  # cadastra tudo de novo no próximo acesso.
  def reset_mfa
    authorize @user, :reset_mfa?
    @user.update!(otp_secret: nil, mfa_enabled_at: nil)
    @user.recovery_codes.destroy_all
    @user.revoke_sessions!
    Audit.record("user.mfa_reset", record: @user, request:)
    redirect_to user_path(@user), notice: "Segundo fator reiniciado. A pessoa cadastra de novo ao entrar."
  end

  def deactivate
    authorize @user, :deactivate?
    @user.update!(deactivated_at: Time.current)
    @user.revoke_sessions!
    Audit.record("user.deactivated", record: @user, request:)
    redirect_to user_path(@user), notice: "Acesso desativado."
  end

  def reactivate
    authorize @user, :update?
    @user.update!(deactivated_at: nil)
    Audit.record("user.reactivated", record: @user, request:)
    redirect_to user_path(@user), notice: "Acesso reativado."
  end

  # O formulário serve para criar e editar: o destino muda, os campos não.
  helper_method :form_url

  def form_url
    @user.new_record? ? users_path : user_path(@user)
  end

  private

  def load_user
    @user = policy_scope(User).find_param!(params[:id])
  end

  # O convite oferece só o que o convidante tem: a tela espelha a policy, e a policy é quem
  # decide — parâmetro forjado cai na regra do SaveUser.
  def load_options
    escopo = Current.access_scope
    @channels = escopo.everything? ? Channel.order(:name) : Channel.where(id: escopo.channel_ids).order(:name)
    @sub_channels = SubChannel.where(channel_id: @channels.select(:id)).order(:name)
    @permissions = Current.user.super_admin? ? Permission::KEYS : Current.user.permissions
  end

  def user_attributes
    dados = params.require(:user).permit(:name, :email_address)
    return dados if action_name == "update"

    # Senha provisória gerada pelo sistema: quem convida não escolhe a senha de outra
    # pessoa, e a troca é obrigatória no primeiro acesso.
    @senha_provisoria = SecureRandom.alphanumeric(14)
    dados.merge(password: @senha_provisoria, provisional_password: @senha_provisoria)
  end

  # O formulário manda uma entrada por caixa marcada, com chaves arbitrárias: o que importa
  # é o par (Master, MIC), e é só ele que sai daqui. O Master de um MIC vem do banco, não
  # do formulário: um campo oculto com o channel_id ao lado de cada MIC fazia todo MIC
  # desmarcado virar concessão do Master inteiro (homologação de 28/09/2026 — erro 500 no
  # índice único, e o convidado receberia mais do que foi marcado).
  def grant_params
    grants = params[:grants]
    return [] if grants.blank?

    grants.keys.filter_map do |chave|
      grant = grants.require(chave).permit(:channel_id, :sub_channel_id)
      if grant[:sub_channel_id].present?
        mic = SubChannel.find_by(id: grant[:sub_channel_id])
        { channel_id: mic.channel_id, sub_channel_id: mic.id } if mic
      elsif grant[:channel_id].present?
        { channel_id: grant[:channel_id].to_i, sub_channel_id: nil }
      end
    end.uniq
  end
end
