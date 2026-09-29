class UsersController < ApplicationController
  before_action :load_user, only: %i[show edit update reset_mfa deactivate reactivate]

  def index
    authorize :user, :index?
    @users = policy_scope(User).includes(:created_by, access_grants: %i[channel sub_channel]).order(:name)
    @usage = usage_of(@users)
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
    @usage = usage_of([ @user ]).fetch(@user.id)
    @events = AuditEvent.where(user: @user).includes(:channel).recent.limit(20)
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
  rescue ActiveRecord::RecordInvalid => error
    # O último administrador geral ativo não se desativa (User#keep_one_active_platform_admin).
    redirect_to user_path(@user), alert: error.record.errors.full_messages.join("; ")
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

  # O uso de cada pessoa sai da trilha, em duas consultas para a listagem inteira: o que se
  # conta é o que a trilha já registra — entradas, exportações, envios. Nada é medido além
  # disso (nem tempo de sessão, nem telas visitadas), porque nada além disso é gravado.
  USAGE_WINDOW = 30.days

  def usage_of(users)
    ids = users.map(&:id)
    counts = AuditEvent.where(user_id: ids, created_at: USAGE_WINDOW.ago..).group(:user_id, :action).count
    last_access = AuditEvent.where(user_id: ids, action: "session.start").group(:user_id).maximum(:created_at)
    ids.to_h do |id|
      [ id, { last_access: last_access[id],
              sessions: counts.fetch([ id, "session.start" ], 0),
              exports: counts.fetch([ id, "report.export" ], 0),
              uploads: counts.fetch([ id, "batch.uploaded" ], 0),
              notes: counts.fetch([ id, "note.saved" ], 0) } ]
    end
  end

  # O convite oferece só o que o convidante tem: a tela espelha a policy, e a policy é quem
  # decide — parâmetro forjado cai na regra do SaveUser.
  def load_options
    escopo = Current.access_scope
    @channels = escopo.everything? ? Channel.order(:name) : Channel.where(id: escopo.channel_ids).order(:name)
    @sub_channels = SubChannel.where(channel_id: @channels.select(:id)).order(:name)
    @permissions = Permission::KEYS.select { |chave| Current.user.permitted?(chave) }
  end

  def user_attributes
    dados = params.require(:user).permit(:name, :email_address)
    # Administrador geral só por administrador geral, e nunca sobre si mesmo — senão o
    # último se rebaixaria por engano. Fora disso o parâmetro é ignorado, não recusado.
    if Current.user.platform_admin? && @user != Current.user && params[:user].key?(:platform_admin)
      dados[:platform_admin] = ActiveModel::Type::Boolean.new.cast(params[:user][:platform_admin])
    end
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
