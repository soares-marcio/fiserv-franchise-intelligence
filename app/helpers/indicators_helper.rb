module IndicatorsHelper
  # O valor na unidade do indicador: percentual com uma casa, ou contagem. Sem valor,
  # travessão — e o title da célula diz por quê.
  def indicator_value(indicator, reading)
    return "—" if reading[:value].nil?
    return reading[:value].to_s unless SubChannelIndicatorRules::INDICATORS.dig(indicator, :unit) == :percent

    number_to_percentage(reading[:value], precision: 1, separator: ",")
  end

  # A conta por trás da célula: a fração do percentual, ou o motivo de não haver leitura.
  def indicator_detail(indicator, reading)
    if reading[:value].nil?
      indicator == :quality ? "Nenhuma proposta com data neste mês" : "Sem Mapa importado desta competência"
    elsif reading[:denominator]
      texto = "#{reading[:numerator]} de #{reading[:denominator]}"
      texto += " · #{pluralize(reading[:pending], 'pendente', 'pendentes')}" if reading[:pending].to_i.positive?
      texto
    end
  end

  def indicator_label(indicator)
    SubChannelIndicatorRules::INDICATORS.dig(indicator, :label)
  end

  def verdict_label(verdict)
    SubChannelIndicatorRules::VERDICT_LABELS.fetch(verdict)
  end
end
