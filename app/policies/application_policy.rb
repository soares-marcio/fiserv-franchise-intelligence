# Base de toda policy. Nega por padrão: um método não escrito é uma porta fechada, e não
# uma porta esquecida aberta.
#
# A pergunta que toda policy faz é sempre a mesma — "este ator tem esta chave?" —, e o
# catálogo de chaves vive em Permission. O recorte de dados (quais Masters e MICs) entra
# nos Scopes, na fase seguinte.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  private

  def permitted?(key)
    user.present? && user.permitted?(key)
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    # Sem resolve escrito, a listagem vem vazia — de novo, o silêncio nega.
    def resolve
      scope.none
    end
  end
end
