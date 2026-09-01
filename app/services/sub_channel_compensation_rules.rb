# Regras do modelo de remuneração da Fiserv, num lugar só. Quem alterar alíquota mexe aqui
# e em nenhum outro lugar. Origem: apresentação de franquias BIN (p. 9-14) e slides
# "Modelo de remuneração" (p. 15-16).
class SubChannelCompensationRules
  # Prêmios de entrada, por faixa de faturamento mensal do EC. A apuração é de marca
  # d'água nos três primeiros meses (M0 = competência inteira do credenciamento): paga-se
  # em M0 o valor da faixa e, em M1/M2, só a diferença quando a faixa do mês supera o já
  # pago. Total da janela = valor da faixa do mês de maior faturamento.
  ACCREDITATION_BRACKETS = [
    { upto: 14_999.99, without_auto: 0, with_auto: 0 },
    { upto: 19_999.99, without_auto: 50, with_auto: 250 },
    { upto: 24_999.99, without_auto: 55, with_auto: 300 },
    { upto: 29_999.99, without_auto: 61, with_auto: 350 },
    { upto: 34_999.99, without_auto: 67, with_auto: 400 },
    { upto: 39_999.99, without_auto: 74, with_auto: 450 },
    { upto: 49_999.99, without_auto: 81, with_auto: 500 },
    { upto: 59_999.99, without_auto: 89, with_auto: 550 },
    { upto: 69_999.99, without_auto: 98, with_auto: 690 },
    { upto: 79_999.99, without_auto: 108, with_auto: 790 },
    { upto: 89_999.99, without_auto: 119, with_auto: 880 },
    { upto: 99_999.99, without_auto: 131, with_auto: 950 },
    { upto: 149_999.99, without_auto: 144, with_auto: 1_300 },
    { upto: 199_999.99, without_auto: 158, with_auto: 1_800 },
    { upto: 9_999_999.00, without_auto: 174, with_auto: 2_200 }
  ].freeze

  # Pago uma única vez, em M0, para EC com acesso ao app.
  DIGITALIZATION_FEE = 30.00

  # A planilha entrega NET MDR em pontos percentuais (0.42 = 0,42%), confirmado por
  # agregados da base real: mediana ~0,30, compatível com MDR típico — como fração seria
  # 30%, absurdo. Se a origem mudar de escala um dia, este é o único ponto de ajuste.
  NET_MDR_SCALE = 1

  # Faixas em pontos percentuais. "Acima de 0,40%" é estrita; as demais usam >= no piso,
  # então 0,40% exato cai na segunda faixa — o documento deixa (0,39%..0,40%] sem dono e
  # fechamos o buraco por baixo. Abaixo de 0,25% a regra existe e é zero.
  NET_MDR_BANDS = [
    { floor: 0.40, strict: true, debit: 0.0009, credit: 0.0018 },
    { floor: 0.35, strict: false, debit: 0.0006, credit: 0.0012 },
    { floor: 0.30, strict: false, debit: 0.0003, credit: 0.0006 },
    { floor: 0.25, strict: false, debit: 0.0001, credit: 0.0002 },
    { floor: 0.00, strict: false, debit: 0.0, credit: 0.0 }
  ].freeze

  # Crescimento como fração (0.20 = 20%), sobre o faturamento incremental. Em 100,00%
  # exato as faixas do slide se sobrepõem; aplicamos a superior.
  ACCELERATOR_BANDS = [
    { floor: 1.00, rate: 0.0010 },
    { floor: 0.50, rate: 0.0007 },
    { floor: 0.30, rate: 0.0005 },
    { floor: 0.20, rate: 0.0004 }
  ].freeze

  # Queda como fração negativa, sobre a remuneração. O slide imprime a terceira faixa
  # como -20% a -20%; o encaixe das demais indica -20% a -29,99% e implementamos assim.
  REDUCER_BANDS = [
    { upto: -0.50, rate: 0.20 },
    { upto: -0.30, rate: 0.15 },
    { upto: -0.20, rate: 0.10 },
    { upto: -0.10, rate: 0.05 }
  ].freeze

  class << self
    def accreditation_bracket_value(revenue, with_auto:)
      return 0 if revenue.nil?

      key = with_auto ? :with_auto : :without_auto
      bracket = ACCREDITATION_BRACKETS.find { |b| revenue <= b[:upto] } || ACCREDITATION_BRACKETS.last
      bracket.fetch(key)
    end

    # net_mdr como veio do banco; a escala é aplicada aqui, num lugar só.
    def mdr_rates(net_mdr)
      return nil if net_mdr.nil?

      scaled = net_mdr.to_f * NET_MDR_SCALE
      band = NET_MDR_BANDS.find { |b| b[:strict] ? scaled > b[:floor] : scaled >= b[:floor] }
      band&.slice(:debit, :credit)
    end

    def accelerator_rate(growth)
      band = ACCELERATOR_BANDS.find { |b| growth >= b[:floor] }
      band ? band[:rate] : 0.0
    end

    def reducer_rate(drop)
      band = REDUCER_BANDS.find { |b| drop <= b[:upto] }
      band ? band[:rate] : 0.0
    end

    # Acelerador OU redutor, nunca os dois: acelerador sobre o incremento, redutor sobre
    # a remuneração. Sem mês anterior positivo não há base de comparação — nenhum ajuste.
    def performance_adjustment(previous:, current:, recurring:)
      return { growth: nil, accelerator: 0.0, reducer: 0.0 } if previous.to_f <= 0

      growth = (current.to_f - previous.to_f) / previous.to_f
      if growth >= ACCELERATOR_BANDS.last[:floor]
        { growth:, accelerator: (current.to_f - previous.to_f) * accelerator_rate(growth), reducer: 0.0 }
      elsif growth.negative?
        { growth:, accelerator: 0.0, reducer: recurring.to_f * reducer_rate(growth) }
      else
        { growth:, accelerator: 0.0, reducer: 0.0 }
      end
    end

    # CASE WHEN para uso em materialized view (que não aceita bind): NULL vira zero para
    # janela sem mês observado não parecer faixa alcançada.
    def accreditation_case_sql(expr, with_auto:)
      key = with_auto ? :with_auto : :without_auto
      branches = ACCREDITATION_BRACKETS.map do |bracket|
        "WHEN (#{expr}) <= #{format('%.2f', bracket[:upto])} THEN #{format('%.2f', bracket.fetch(key))}"
      end
      <<~SQL.strip
        CASE
          WHEN (#{expr}) IS NULL THEN 0
          #{branches.join("\n  ")}
          ELSE #{format('%.2f', ACCREDITATION_BRACKETS.last.fetch(key))}
        END
      SQL
    end
  end
end
