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
      @profile = Platform::OrganizationProfile.new(@organization)
      @platform_events = platform_events_about(@organization)
    end

    # O histórico completo da organização, lido de propósito fora do Scope da policy — que
    # para a plataforma só devolve os eventos de plataforma. A tela não mostra o Master: a
    # plataforma vê a atividade (quem entrou, quem enviou arquivo), não a carteira.
    def history
      authorize :organization, :history?
      @organization = load_organization
      events = AuditEvent.where(organization_id: @organization.id).recent
      @page = [ params[:page].to_i, 1 ].max
      offset = (@page - 1) * AuditEventsController::PER_PAGE
      @events = events.includes(:user).limit(AuditEventsController::PER_PAGE).offset(offset)
      @has_more = events.limit(1).offset(offset + AuditEventsController::PER_PAGE).any?
    end

    # Renomear a pedido da organização. O nome em branco chega ao modelo como string vazia,
    # que ele recusa — nulo seria "ainda sem nome", e passaria.
    def rename
      authorize :organization, :rename?
      @organization = load_organization
      previous_name = @organization.name
      if @organization.update(name: params[:name].to_s.strip)
        Audit.record("organization.renamed", record: @organization, request:,
          metadata: { de: previous_name, para: @organization.name })
        redirect_to platform_organization_path(@organization), notice: "Organização renomeada."
      else
        redirect_to platform_organization_path(@organization),
          alert: "Nome não aceito: #{@organization.errors.full_messages.join('; ')}"
      end
    end

    def suspend
      authorize :organization, :suspend?
      @organization = load_organization
      @organization.suspend!
      Audit.record("organization.suspended", record: @organization, request:)
      redirect_to platform_organization_path(@organization),
        notice: "Organização suspensa. Ninguém dela entra até a reativação; nada foi apagado."
    end

    def reactivate
      authorize :organization, :reactivate?
      @organization = load_organization
      @organization.reactivate!
      Audit.record("organization.reactivated", record: @organization, request:)
      redirect_to platform_organization_path(@organization), notice: "Organização reativada."
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

    def load_organization
      policy_scope(Organization).find_param!(params[:id])
    end

    # O que a plataforma fez sobre esta organização: os eventos dela são de plataforma (sem
    # organização) e apontam para a organização ou para uma conta dela.
    def platform_events_about(organization)
      policy_scope(AuditEvent)
        .where(record: organization)
        .or(policy_scope(AuditEvent).where(record_type: "User", record_id: organization.users.select(:id)))
        .includes(:user).recent.limit(20)
    end

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
