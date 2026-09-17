# Indicadores do Anexo B do Contrato de Micro Franquia (Circular de Oferta de Franquia,
# v1.2023, p. 35): sete critérios mensais, cada um com três leituras — Adequado, Atenção e
# Risco. As faixas vivem só aqui.
#
# Eles condicionam a Participação: a Definição 26 a descreve como paga "mediante o
# cumprimento dos Indicadores", e a cláusula 12.2 (xx) dá à Franqueadora o direito de
# rescindir por "descumprimento do estabelecido no Anexo B por prazo igual ou superior a
# 60 (sessenta) dias". O anexo não diz o que é descumprir; o portal conta só o Risco, e
# como a apuração é mensal, dois meses fechados seguidos alcançam os 60 dias.
#
# O portal apura cinco dos sete. Os dois que ficam de fora, e por quê:
# - Índice de reclamações: reclamações recebidas pela Fiserv — não existe no arquivo.
# - Ordens canceladas: também sem coluna; e as faixas do anexo se sobrepõem ("entre 0% e
#   4%" adequado, "≤ 4,01%" atenção, "≥ 5%" risco), então nem com dado haveria leitura única.
#
# Duas leituras que o texto do anexo obriga a declarar:
# - "Atividade dos Estabelecimentos" está escrito como "percentual com pelo menos uma
#   transação", com Adequado ≤ 5% — ao pé da letra, uma carteira toda ativa seria Risco. As
#   faixas só fazem sentido para a fração **sem** transação, e é assim que o portal lê.
#   Não "corrija" para o texto literal.
# - As fronteiras têm duas casas (≤ 10% adequado, ≥ 10,01% atenção): o percentual apurado é
#   arredondado a duas casas antes de comparar, senão 10,004% não cairia em faixa nenhuma.
class SubChannelIndicatorRules
  # adequate e risk são as fronteiras inclusivas do anexo; o que sobra entre elas é Atenção.
  # "< 5" credenciamentos, em inteiros, é "≤ 4".
  INDICATORS = {
    quality: { label: "Qualidade das indicações", unit: :percent, higher_is_better: false,
      adequate: 10, risk: 25.01 },
    accreditations: { label: "Credenciamentos", unit: :count, higher_is_better: true,
      adequate: 10, risk: 4 },
    volume: { label: "Volume transacional", unit: :percent, higher_is_better: true,
      adequate: 92, risk: 88 },
    attrition: { label: "Descredenciamento", unit: :percent, higher_is_better: false,
      adequate: 2, risk: 5.01 },
    activity: { label: "ECs sem transação", unit: :percent, higher_is_better: false,
      adequate: 5, risk: 10.01 }
  }.freeze

  NOT_MEASURABLE = {
    complaints: "Índice de reclamações",
    cancelled_orders: "Ordens canceladas"
  }.freeze

  VERDICT_LABELS = { adequate: "Adequado", attention: "Atenção", risk: "Risco" }.freeze

  # Volume transacional: ECs "com volume de transações com cartões de crédito e débito
  # acima de R$ 10.000,00" no mês.
  VOLUME_THRESHOLD = 10_000

  # Vocabulário real de STATUS DA PROPOSTA (aba Ativação). Medido em 17/09/2026, 417 linhas:
  # "Boarded to BWA" 285, "Credit Declined" 80, "Pending QC" 52. A qualidade das indicações
  # é "percentual de pedidos rejeitados": recusadas sobre os pedidos do mês, pendentes na
  # base — um pedido pendente é pedido, e ainda pode ser recusado. A alternativa (recusadas
  # sobre decididas) lê mais alto; a tela mostra as pendentes para a conta ser conferível.
  REJECTED_STATUS = "Credit Declined"
  PENDING_STATUS = "Pending QC"

  # Meses fechados seguidos em Risco a partir dos quais a cláusula 12.2 (xx) alcança o MIC.
  TERMINATION_MONTHS = 2

  def self.verdict(indicator, value)
    return if value.nil?

    rule = INDICATORS.fetch(indicator)
    value = value.round(2)
    if rule[:higher_is_better]
      return :adequate if value >= rule[:adequate]
      return :risk if value <= rule[:risk]
    else
      return :adequate if value <= rule[:adequate]
      return :risk if value >= rule[:risk]
    end
    :attention
  end
end
