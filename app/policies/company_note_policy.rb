class CompanyNotePolicy < ApplicationPolicy
  def show? = permitted?(Permission::NOTES_READ)
  alias_method :index?, :show?

  def edit? = permitted?(Permission::NOTES_WRITE)
  alias_method :update?, :edit?
  alias_method :create?, :edit?
end
