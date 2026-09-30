class SubChannelPolicy < ApplicationPolicy
  def show? = permitted?(Permission::REPORTS_READ)

  # MIC fora do escopo não é 403, é 404: a tela já responde assim quando o MIC é de outro
  # Master, e dizer "existe, mas você não pode" conta o que não precisa ser contado.
  class Scope < ApplicationPolicy::Scope
    def resolve
      access = AccessScope.for(user)
      scope.where(channel_id: access.full_channel_ids).or(scope.where(id: access.sub_channel_ids))
    end
  end
end
