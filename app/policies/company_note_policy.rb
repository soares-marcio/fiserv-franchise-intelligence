class CompanyNotePolicy < ApplicationPolicy
  def show? = permitted?(Permission::NOTES_READ)
  alias_method :index?, :show?

  def edit? = permitted?(Permission::NOTES_WRITE)
  alias_method :update?, :edit?
  alias_method :create?, :edit?

  # A anotação é presa ao CNPJ e não tem canal — o mesmo CNPJ pode existir em dois Masters.
  # A regra, então, é de domínio: vê a anotação quem tem ao menos um EC daquele CNPJ no
  # próprio escopo.
  #
  # A consequência, que fica documentada e não resolvida aqui: dois atores de Masters
  # diferentes com o mesmo cliente dividem a mesma anotação e escrevem por cima um do
  # outro. Isso já era verdade antes do login; o que muda é que agora se sabe quem escreveu.
  class Scope < ApplicationPolicy::Scope
    def resolve
      access = AccessScope.for(user)
      scope.where(cnpj: Company.where(id: Establishment.in_scope(access).select(:company_id))
        .select(:cnpj))
    end
  end
end
