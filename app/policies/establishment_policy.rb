class EstablishmentPolicy < ApplicationPolicy
  def index? = permitted?(Permission::ESTABLISHMENTS_READ)
  alias_method :show?, :index?

  def export? = permitted?(Permission::REPORTS_EXPORT)
end
