class SubChannelPolicy < ApplicationPolicy
  # Mesma regra do Master: apaga o administrador da organização, restaura a plataforma.
  def destroy?
    return false unless user&.organization_admin?

    !record.is_a?(SubChannel) || record.channel.organization_id == user.organization_id
  end

  def restore? = platform?

  # MIC fora do escopo não é 403, é 404: a tela já responde assim quando o MIC é de outro
  # Master, e dizer "existe, mas você não pode" conta o que não precisa ser contado.
  class Scope < ApplicationPolicy::Scope
    def resolve
      access = AccessScope.for(user)
      scope.where(channel_id: access.full_channel_ids).or(scope.where(id: access.sub_channel_ids))
    end
  end
end
