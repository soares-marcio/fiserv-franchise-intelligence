# Policy sem registro: as telas de relatório não têm um objeto próprio, o que elas mostram
# é a carteira recortada pelo escopo do ator.
class ReportPolicy < ApplicationPolicy
  def index? = permitted?(Permission::REPORTS_READ)
  alias_method :show?, :index?

  # Exportar é permissão própria, e não um detalhe de "ver": o arquivo larga a paginação e
  # leva o recorte inteiro — a carteira toda num anexo de e-mail.
  def export? = permitted?(Permission::REPORTS_EXPORT)
end
