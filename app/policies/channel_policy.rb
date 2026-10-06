class ChannelPolicy < ApplicationPolicy
  # Apagar é do administrador da organização dona do Master; restaurar, só da plataforma.
  # Colaborador e delegado com o Master inteiro não apagam: a decisão é da organização.
  def destroy? = organization_admin_of?(record)
  def restore? = platform?

  private

  def organization_admin_of?(channel)
    return false unless user&.organization_admin?

    !channel.is_a?(Channel) || channel.organization_id == user.organization_id
  end

  public

  class Scope < ApplicationPolicy::Scope
    def resolve
      access = AccessScope.for(user)
      scope.where(id: access.channel_ids)
    end
  end
end
