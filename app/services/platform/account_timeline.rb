module Platform
  # O ciclo de vida de uma conta, como a plataforma o lê: convite, primeiro acesso, segundo
  # fator, senha, validade, permissões em números, desativação e reativação. A atividade na
  # carteira (exportar, anotar, importar) é da organização e fica de fora, assim como as
  # entradas uma a uma — viram contagem e datas no resumo.
  class AccountTimeline
    ABOUT_ACCOUNT = %w[user.created organization_admin.created user.updated user.access_changed
      user.access_validity_changed user.mfa_reset user.deactivated user.reactivated].freeze
    BY_ACCOUNT = %w[mfa.enrolled password.changed mfa.recovery_code_used session.expired_access].freeze

    def initialize(user)
      @user = user
    end

    def events
      AuditEvent.where(action: ABOUT_ACCOUNT, record_type: "User", record_id: @user.id)
        .or(AuditEvent.where(action: BY_ACCOUNT, user_id: @user.id))
        .includes(:user).order(created_at: :desc).limit(50)
    end

    def first_access = logins.minimum(:created_at)
    def last_access = logins.maximum(:created_at)
    def logins_count = logins.count
    def refused_count = AuditEvent.where(action: %w[session.failed mfa.failed], user_id: @user.id).count

    private

    def logins = AuditEvent.where(action: "session.start", user_id: @user.id)
  end
end
