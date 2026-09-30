module Platform
  # A visão macro da plataforma: cada organização, seus administradores e os convidados de
  # cada um — nome, e-mail, situação e último acesso. Nenhum nome de Master, nenhum número
  # de carteira: a plataforma cria contas, não lê dado.
  class OrganizationsController < ApplicationController
    def index
      authorize :organization, :index?
      @organizations = policy_scope(Organization).includes(:users).order(Arel.sql("name NULLS LAST"), :id)
      @last_access = last_access_of(User.where(organization_id: @organizations.map(&:id)))
    end

    def show
      authorize :organization, :show?
      @organization = policy_scope(Organization).find_param!(params[:id])
      @admins = @organization.users.where(organization_admin: true).order(:name)
      @members = @organization.users.where(organization_admin: false).includes(:created_by).order(:name)
      @last_access = last_access_of(@organization.users)
    end

    def new
      authorize :organization, :create?
      @admin = User.new
    end

    # Cria a organização (sem nome — o administrador a nomeia no primeiro acesso) e o seu
    # administrador, de uma vez: uma organização sem administrador não teria como começar.
    def create
      authorize :organization, :create?
      admin = Operations::CreateOrganizationAdmin.call(**admin_params, actor: Current.user)
      Audit.record("organization.created", record: admin.organization, request:)
      Audit.record("organization_admin.created", record: admin, request:, metadata: { alvo: admin.email_address })
      redirect_to platform_organization_path(admin.organization),
        notice: "Organização criada. A senha provisória de #{admin.name} fica nesta tela até a troca."
    rescue ActiveRecord::RecordInvalid => error
      @admin = error.record
      render :new, status: :unprocessable_entity
    end

    private

    def admin_params
      params.require(:user).permit(:name, :email_address).to_h.symbolize_keys
    end

    # Único dado de uso que a plataforma lê, e de propósito: o último login de cada conta.
    # Vem direto da trilha, fora do Scope da policy — que para a plataforma só devolve os
    # eventos de plataforma.
    def last_access_of(users)
      AuditEvent.where(user_id: users.select(:id), action: "session.start").group(:user_id).maximum(:created_at)
    end
  end
end
