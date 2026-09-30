class CompanyNotePolicy < ApplicationPolicy
  def show? = permitted?(Permission::NOTES_READ)
  alias_method :index?, :show?

  def edit? = permitted?(Permission::NOTES_WRITE)
  alias_method :update?, :edit?
  alias_method :create?, :edit?

  # A anotação é da organização e presa ao CNPJ, sem canal — o mesmo CNPJ pode existir em
  # dois Masters da mesma organização. A regra, então, é de domínio: vê a anotação quem tem
  # ao menos um EC daquele CNPJ no próprio escopo, dentro da própria organização.
  #
  # A consequência, documentada: dois atores de Masters diferentes **da mesma organização**
  # com o mesmo cliente dividem a mesma anotação e escrevem por cima um do outro. Entre
  # organizações isso não acontece — são anotações distintas.
  class Scope < ApplicationPolicy::Scope
    def resolve
      access = AccessScope.for(user)
      return scope.none if access.organization_id.nil?

      scope.where(organization_id: access.organization_id,
        cnpj: Company.where(id: Establishment.in_scope(access).select(:company_id)).select(:cnpj))
    end
  end
end
