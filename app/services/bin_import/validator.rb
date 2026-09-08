module BinImport
  class Validator
    attr_reader :previous_period, :current_period, :covered_periods

    def initialize(rows)
      @rows = rows
      @map_rows = rows.fetch("Mapa de Clientes BIN")
      @revenue_rows = rows.fetch("Faturamento")
    end

    def validate!
      validate_identity!
      derive_competencies!
      self
    end

    def validate_identity!
      validate_single_channel!
      validate_required_values!
      validate_ec_identity!
      validate_revenue_membership!
      validate_daily_totals!
      self
    end

    private

    def validate_single_channel!
      report_ids = values(@map_rows, "REPORT_ID")
      channels = @rows.values.flat_map { |sheet_rows| values(sheet_rows, "CANAL") }.uniq
      unless report_ids.one?
        raise ArgumentError, "A coluna REPORT_ID do Mapa precisa ter um único valor no arquivo " \
          "inteiro, e este traz #{report_ids.size == 0 ? 'nenhum' : "#{report_ids.size}: #{report_ids.to_sentence}"}. " \
          "Cada arquivo cobre uma carteira só; separe as carteiras em arquivos diferentes."
      end
      # A ausência de CANAL não recusa o arquivo: o import cria o canal fictício
      # ChannelResolver::FALLBACK_NAME e marca cada linha sem CANAL como anomalia.
      if channels.many?
        raise ArgumentError, "O arquivo traz mais de um CANAL: #{channels.to_sentence}. " \
          "Cada arquivo cobre uma carteira só; separe os canais em arquivos diferentes."
      end
    end

    def validate_required_values!
      @rows.each do |sheet_name, sheet_rows|
        required = Template::REQUIRED_HEADERS.fetch(sheet_name)
        sheet_rows.each do |row|
          missing = required.select { |header| row[header].blank? }
          missing.delete("CANAL") if canal_dispensavel?(sheet_name)
          next if missing.empty?

          raise ArgumentError, "Na aba \"#{sheet_name}\", linha #{row['_row_number']} da planilha, " \
            "#{missing.one? ? 'o campo obrigatório está vazio' : 'há campos obrigatórios vazios'}: " \
            "#{missing.join(', ')}. Preencha #{missing.one? ? 'a célula' : 'as células'} e envie de novo."
        end
      end
    end

    # O Mapa sempre tolera linha sem CANAL — vira anomalia. As outras abas só toleram quando
    # o arquivo inteiro chega sem canal: aí a carteira entra sob o nome fictício. Arquivo
    # parcialmente preenchido continua sendo recusado, porque aí falta dado, não a coluna.
    def canal_dispensavel?(sheet_name)
      sheet_name == "Mapa de Clientes BIN" || sem_canal_no_arquivo?
    end

    def sem_canal_no_arquivo?
      return @sem_canal unless @sem_canal.nil?

      @sem_canal = @rows.values.flat_map { |sheet_rows| values(sheet_rows, "CANAL") }.empty?
    end

    def validate_ec_identity!
      identities = Hash.new { |hash, key| hash[key] = [] }
      @rows.each_value do |sheet_rows|
        sheet_rows.each do |row|
          ec = Normalizer.ec(row["EC"])
          next if ec.blank?

          identities[ec] << Normalizer.cnpj(row["CNPJ"])
        end
      end
      changed = identities.find { |_ec, cnpjs| cnpjs.uniq.many? }
      if changed
        raise ArgumentError, "O EC #{changed.first} aparece com mais de um CNPJ dentro deste " \
          "mesmo arquivo. Um EC pertence a um CNPJ só: confira as linhas desse EC nas três abas."
      end
    end

    def validate_revenue_membership!
      map_ecs = @map_rows.to_set { |row| Normalizer.ec(row["EC"]) }
      missing = @revenue_rows.filter_map do |row|
        ec = Normalizer.ec(row["EC"])
        ec unless map_ecs.include?(ec)
      end
      if missing.any?
        amostra = missing.first(10).join(", ")
        raise ArgumentError, "#{missing.size} #{missing.one? ? 'EC da aba Faturamento não está' : 'ECs da aba Faturamento não estão'} " \
          "na aba Mapa de Clientes BIN: #{amostra}#{'…' if missing.size > 10}. Todo EC que fatura " \
          "precisa estar no Mapa — exporte as duas abas do mesmo momento."
      end
    end

    def validate_daily_totals!
      @revenue_rows.each do |row|
        validate_daily_series!(row, "_M_1", "fat_total_m1")
        validate_daily_series!(row, "", "FATURAMENTO TOTAL DESTE MÊS")
      end
    end

    def validate_daily_series!(row, suffix, total_header)
      total = Normalizer.decimal(row[total_header]) || 0
      sum = (1..31).sum { |day| Normalizer.decimal(row[format("DIA %02d%s", day, suffix)]) || 0 }
      return if sum == total

      raise ArgumentError, "Na aba Faturamento, linha #{row['_row_number']} da planilha (EC " \
        "#{row['EC']}), a soma dos dias não bate com a coluna \"#{total_header}\": os dias somam " \
        "#{format('%.2f', sum)} e a coluna traz #{format('%.2f', total)}. Confira se algum dia " \
        "ficou vazio ou se o total foi editado à mão."
    end

    def derive_competencies!
      @covered_periods = covered_periods_from_headers!
      map_by_ec = @map_rows.index_by { |row| Normalizer.ec(row["EC"]) }
      @previous_period = matching_period(map_by_ec, "fat_total_m1")
      @current_period = matching_period(map_by_ec, "FATURAMENTO TOTAL DESTE MÊS")
      return if @current_period == @previous_period.next_month

      raise ArgumentError, "As duas competências do arquivo não são meses seguidos: a coluna " \
        "\"fat_total_m1\" bate com #{I18n.l(@previous_period, format: '%B de %Y')} e " \
        "\"FATURAMENTO TOTAL DESTE MÊS\" com #{I18n.l(@current_period, format: '%B de %Y')}. " \
        "A comparação exige mês anterior e mês atual: confira se as colunas de volume do Mapa " \
        "e as de faturamento vieram da mesma exportação."
    end

    # As competências cobertas vêm do próprio arquivo: a planilha avança um mês por
    # semana, e uma lista fixa derrubaria o import na primeira virada.
    def covered_periods_from_headers!
      months = (@map_rows.first || {}).keys
        .filter_map { |header| header[/\AVOLUME DE FATURAMENTO TOTAL (\d{6})\z/, 1] }
      if months.empty?
        raise ArgumentError, "A aba Mapa de Clientes BIN não tem nenhuma coluna " \
          "\"VOLUME DE FATURAMENTO TOTAL AAAAMM\". São elas que dizem quais competências o " \
          "arquivo cobre; sem elas não há o que comparar."
      end

      months.sort.map { |month| Date.strptime(month, "%Y%m") }
    end

    def matching_period(map_by_ec, revenue_header)
      scores = @covered_periods.to_h do |period|
        volume_header = "VOLUME DE FATURAMENTO TOTAL #{period.strftime('%Y%m')}"
        score = @revenue_rows.count do |row|
          map_value = map_by_ec[Normalizer.ec(row["EC"])]&.fetch(volume_header, nil)
          map_value.present? && Normalizer.decimal(map_value) == (Normalizer.decimal(row[revenue_header]) || 0)
        end
        [ period, score ]
      end
      best = scores.max_by { |_period, score| score }
      meses = @covered_periods.map { |period| I18n.l(period, format: "%b/%Y") }.to_sentence
      if best.last.zero?
        raise ArgumentError, "Não deu para descobrir de que mês é a coluna \"#{revenue_header}\": " \
          "o valor dela não bateu com nenhuma coluna de volume do Mapa (#{meses}). As duas abas " \
          "precisam vir da mesma exportação."
      end
      if scores.values.count(best.last) > 1
        raise ArgumentError, "A coluna \"#{revenue_header}\" bateu igualmente com mais de uma " \
          "competência do Mapa (#{meses}), então não dá para dizer de que mês ela é. Isso " \
          "costuma acontecer quando dois meses trazem os mesmos valores."
      end

      best.first
    end

    def values(rows, header)
      rows.filter_map { |row| row[header].to_s.strip.presence }.uniq
    end
  end
end
