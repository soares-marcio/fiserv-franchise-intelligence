# Policy sem registro: as telas de relatório não têm um objeto próprio, o que elas mostram
# é a carteira recortada pelo escopo do ator.
#
# Uma pergunta por item do menu, e cada tela de detalhe responde pela do item de onde se
# chega a ela — o mapa ação → item fica no ReportsController.
class ReportPolicy < ApplicationPolicy
  def revenue? = permitted?(Permission::REPORTS_REVENUE)
  def clover? = permitted?(Permission::REPORTS_CLOVER)
  def weekly? = permitted?(Permission::REPORTS_WEEKLY)
  def three_months? = permitted?(Permission::REPORTS_THREE_MONTHS)
  def recurring? = permitted?(Permission::REPORTS_RECURRING)
  def indicators? = permitted?(Permission::REPORTS_INDICATORS)

  # Algum item de relatório: é o que decide se o grupo aparece no menu.
  def any? = Permission::REPORT_KEYS.any? { |key| permitted?(key) }

  # Exportar é permissão própria, e não um detalhe de "ver": o arquivo larga a paginação e
  # leva o recorte inteiro — a carteira toda num anexo de e-mail. A tela de onde se exporta
  # já foi autorizada pelo item dela.
  def export? = permitted?(Permission::REPORTS_EXPORT)
end
