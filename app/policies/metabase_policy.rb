# A tela mostra host, porta, banco e usuário de conexão do papel somente leitura: é dado de
# infraestrutura, não relatório.
class MetabasePolicy < ApplicationPolicy
  def show? = permitted?(Permission::METABASE_READ)
end
