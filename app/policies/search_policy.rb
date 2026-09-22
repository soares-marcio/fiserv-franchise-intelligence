# A busca atravessa a carteira por qualquer identificador; quem pode usá-la é quem já pode
# ver estabelecimento.
class SearchPolicy < ApplicationPolicy
  def index? = permitted?(Permission::ESTABLISHMENTS_READ)
end
