# A trilha diz quem fez o quê no portal inteiro: é leitura de administração, não de
# operação. Fica com quem administra acessos.
class AuditEventPolicy < ApplicationPolicy
  def index? = permitted?(Permission::USERS_INVITE)

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Transitório: a trilha só ganha organization_id na fase da trilha; até lá o
      # administrador da organização lê tudo, como o antigo super admin.
      return scope.all if user&.organization_admin?
      return scope.none unless user&.permitted?(Permission::USERS_INVITE)

      # Um admin delegado vê o que aconteceu nos Masters que ele administra, mais os
      # eventos sem canal (entrada, senha, MFA) dos usuários que ele alcança.
      scope.where(channel_id: AccessScope.for(user).channel_ids)
        .or(scope.where(channel_id: nil))
    end
  end
end
