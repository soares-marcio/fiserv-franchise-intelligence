class ChannelPolicy < ApplicationPolicy
  def show? = permitted?(Permission::REPORTS_READ)

  class Scope < ApplicationPolicy::Scope
    def resolve
      access = AccessScope.for(user)
      return scope.all if access.everything?

      scope.where(id: access.channel_ids)
    end
  end
end
