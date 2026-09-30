# A organização é administrada de dois lugares: a plataforma a cria, lista e lhe dá
# administradores; o administrador dela lhe dá o nome. Ninguém mais a toca.
class OrganizationPolicy < ApplicationPolicy
  def index? = platform?
  def show? = platform?
  def create? = platform?
  def new? = create?
  def create_admin? = platform?
  # Suporte sobre a organização inteira: renomear a pedido e fechar ou reabrir a porta.
  def rename? = platform?
  def suspend? = platform?
  def reactivate? = platform?

  # Nomear é do administrador da própria organização, no primeiro acesso.
  def update? = user.present? && user.organization_admin? && record.id == user.organization_id
  alias_method :edit?, :update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.platform_admin? ? scope.all : scope.none
    end
  end
end
