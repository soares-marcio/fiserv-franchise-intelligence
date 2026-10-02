# A trilha diz quem fez o quê: é leitura de administração, não de operação. Cada organização
# lê a sua; a plataforma lê só os eventos de plataforma — os que não têm organização.
class AuditEventPolicy < ApplicationPolicy
  def index? = platform? || permitted?(Permission::USERS_INVITE)

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.where(organization_id: nil) if user&.platform_admin?
      return scope.none unless user&.permitted?(Permission::USERS_INVITE)

      base = scope.where(organization_id: user.organization_id)
      return base if user.organization_admin?

      # O delegado vê o que aconteceu nos Masters que administra, mais os eventos sem canal
      # (entrada, senha, MFA) **dos usuários que ele alcança** — e não de todo mundo, que era
      # o que um `.or(channel_id: nil)` sem filtro de usuário deixava passar.
      reach = UserPolicy::Scope.new(user, User).resolve.select(:id)
      base.where(channel_id: AccessScope.for(user).channel_ids)
        .or(base.where(channel_id: nil, user_id: reach))
    end
  end
end
