module BinImport
  class Template
    FATURAMENTO_BASE = [
      "HIERARQUIA", "CANAL", "SUB-CANAL", "EC", "CNPJ", "RAZÃO SOCIAL", "NOME FANTASIA",
      "STATUS DO CONTRATO", "DATA DE SUSPENSÃO", "DATA DA ÚLT TRANSAÇÃO",
      "ATIVO NOS ÚLTIMOS 60 DIAS?", "ENDEREÇO", "CEP", "CIDADE", "ESTADO",
      "TELEFONE DO TRABALHO", "CNAE", "DESCRIÇÃO DO CNAE", "fat_total_m1"
    ].freeze
    ATIVACAO_HEADERS = [
      "HIERARQUIA", "CANAL", "SUB-CANAL", "NR DA PROPOSTA", "DATA DA PROPOSTA", "EC", "CNPJ",
      "RAZÃO SOCIAL", "NOME FANTASIA", "STATUS DA PROPOSTA", "DATA DE AFILIAÇÃO",
      "DATA DE INSTALAÇÃO", "DATA DE ATIVAÇÃO", "TICKET MÉDIO", "FATURAMENTO ANUAL PREVISTO"
    ].freeze
    MAPA_BASE = [
      "REPORT_ID", "HIERARQUIA", "CANAL", "SUB-CANAL", "EC", "CNPJ", "TIPO DE PESSOA",
      "NOME FANTASIA", "RAZÃO SOCIAL", "RAMO DE ATIVIDADE", "CÓDIGO DO CNAE",
      "DESCRIÇÃO DO CNAE", "STATUS DO CONTRATO", "MELHOR CONVERSA", "TELEFONE DO TRABALHO",
      "ENDEREÇO", "CEP", "NOME CONTATO 1", "NOME CONTATO 2", "CIDADE", "ESTADO", "Ilha PJ+",
      "vip_boarding_date", "motivo_entrada_vip", "SEGMENTO PRESUMIDO", "SEGMENTO PERFORMADO",
      "STATUS DE RECIPROCIDADE", "FATURAMENTO MÉDIO ÚLTIMOS 3 MESES", "MAIOR FATURAMENTO",
      "Diferença Fat M-1 x M-2", "Diferença Fat %", "Cluster Queda Fat", "ATIVO NO MÊS ATUAL?",
      "ATIVO NO ULTIMO MÊS?", "ATIVO NOS ÚLTIMOS 30 DIAS?", "DATA DA ÚLT TRANSAÇÃO",
      "DATA DE CREDENCIAMENTO", "DATA DE INSTALAÇÃO", "DATA DE ATIVAÇÃO", "DATA DE SUSPENSÃO",
      "ULTIMO ACESSO NO APP", "SOLUÇÕES FINANCEIRAS", "STATUS ANTECIP AUTO NO BOARDING",
      "STATUS ANTECIP AUTO NO BOARDING.1", "VOLUME_PRE_APROVADO", "PRAZO_PRE_APROVADO",
      "TAXA_PRE_APROVADA", "PARCELA_PRE_APROVADA", "POSSUI LINK PGTO", "QTDE TAP ON PHONE",
      "QTDE SMART POS", "QTDE DEMAIS POS", "QTDE MPS", "QTDE PIN", "QTDE TEF",
      "QTDE OUTROS TERMINAIS", "QTDE TOTAL TERMINAIS", "NET MDR"
    ].freeze
    NAME_HEADERS = [ "RAZÃO SOCIAL", "NOME FANTASIA" ].freeze
    # A Fiserv entrega as abas Faturamento e Ativacao com os cabeçalhos de razão social e
    # nome fantasia trocados entre si; o Mapa de Clientes BIN vem com os cabeçalhos corretos.
    INVERTED_NAME_SHEETS = %w[Faturamento Ativacao].freeze
    # As competências das colunas de volume avançam a cada planilha semanal; só o
    # conjunto de referência das planilhas sintéticas fica fixo. A validação real aceita
    # qualquer conjunto de meses, desde que as quatro famílias tragam o mesmo.
    DEFAULT_VOLUME_MONTHS = %w[202604 202605 202606 202607 202608].freeze
    VOLUME_FAMILIES = [
      "VOLUME DE FATURAMENTO TOTAL", "VOLUME DE FATURAMENTO CRÉDITO",
      "VOLUME DE FATURAMENTO DÉBITO", "VOLUME DE ANTECIPAÇÃO"
    ].freeze
    VOLUME_HEADER_PATTERN =
      /\A(#{VOLUME_FAMILIES.map { |family| Regexp.escape(family) }.join("|")}) (\d{6})\z/
    MAPA_FIXED_HEADERS = [ *MAPA_BASE, "agenda_semanal" ].freeze
    EXPECTED_HEADERS = {
      "Faturamento" => [
        *FATURAMENTO_BASE, *(1..31).map { |day| format("DIA %02d_M_1", day) },
        "FATURAMENTO TOTAL DESTE MÊS", *(1..31).map { |day| format("DIA %02d", day) }
      ].freeze,
      "Ativacao" => ATIVACAO_HEADERS,
      "Mapa de Clientes BIN" => [
        *MAPA_BASE, *VOLUME_FAMILIES.flat_map { |family| DEFAULT_VOLUME_MONTHS.map { |month| "#{family} #{month}" } },
        "agenda_semanal"
      ].freeze
    }.freeze
    SHEETS = EXPECTED_HEADERS.keys.freeze
    REQUIRED_HEADERS = {
      "Faturamento" => [ "CANAL", "SUB-CANAL", "EC", "CNPJ", "STATUS DO CONTRATO" ],
      "Ativacao" => [ "CANAL", "SUB-CANAL", "NR DA PROPOSTA", "EC", "CNPJ" ],
      "Mapa de Clientes BIN" => [ "REPORT_ID", "CANAL", "SUB-CANAL", "EC", "CNPJ", "STATUS DO CONTRATO" ]
    }.freeze

    def self.register!(workbook = nil)
      template = ImportTemplate.find_or_create_by!(name: "Template BIN v1") do |record|
        record.sheet_names = SHEETS
      end
      headers_by_sheet(workbook).each do |sheet_name, headers|
        headers.each do |header|
          template.import_template_columns.find_or_create_by!(sheet_name:, source_header: header) do |column|
            column.required = REQUIRED_HEADERS.fetch(sheet_name).include?(header)
            column.normalization_rule = rule_for(sheet_name, header)
          end
        end
      end
      template
    end

    # Com um workbook em mãos, as colunas de volume registradas são as que o arquivo
    # trouxe — meses novos entram sozinhos, pelo find_or_create acima.
    def self.headers_by_sheet(workbook)
      return EXPECTED_HEADERS unless workbook

      workbook.default_sheet = "Mapa de Clientes BIN"
      EXPECTED_HEADERS.merge("Mapa de Clientes BIN" => workbook.row(1).map(&:to_s))
    end

    def self.validate!(workbook)
      # Abas além das três são ignoradas: o analista costuma anexar planilhas de análise
      # ao mesmo arquivo, e o importador só lê as abas pelo nome.
      missing = SHEETS - workbook.sheets
      if missing.any?
        raise ArgumentError,
          "O arquivo não tem #{missing.one? ? 'a aba' : 'as abas'} #{lista(missing)}. " \
            "Abas encontradas: #{lista(workbook.sheets)}. O nome da aba precisa ser exatamente " \
            "esse; abas a mais o arquivo pode ter."
      end

      EXPECTED_HEADERS.each do |sheet_name, expected|
        workbook.default_sheet = sheet_name
        actual = workbook.row(1).map(&:to_s)
        # As competências dos volumes do Mapa avançam toda semana: a parte fixa continua
        # comparada ao literal, e os meses são validados por forma, não por lista.
        next validate_mapa_headers!(actual) if sheet_name == "Mapa de Clientes BIN"

        check_headers!(sheet_name, expected:, actual:)
      end
    end

    # Coluna a mais não recusa o arquivo: a planilha da Fiserv ganha colunas com o tempo, e o
    # importador lê as células pelo nome do cabeçalho — o que sobra é ignorado. Coluna que
    # falta continua sendo erro, e renomear uma coluna aparece como falta, então a proteção
    # contra renome segue de pé.
    def self.check_headers!(sheet_name, expected:, actual:)
      missing = expected - actual
      return if missing.empty?

      extras = actual - expected
      raise ArgumentError, header_error_message(sheet_name, missing, extras)
    end

    # A mensagem é lida por quem tem o arquivo aberto e precisa consertá-lo sozinho: diz a
    # aba, os nomes que faltam, o que apareceu no lugar e o que fazer com isso.
    # Plural escrito à mão: pluralize e to_sentence flexionam em inglês, e a mensagem é lida
    # em português por quem está com a planilha aberta.
    def self.header_error_message(sheet_name, missing, extras)
      uma = missing.one?
      rotulo = uma ? "a coluna" : "as colunas"
      pista = if extras.any?
        "No lugar apareceu #{lista(extras)}, então é provável que #{uma ? 'ela tenha' : 'elas tenham'} " \
          "sido #{uma ? 'renomeada' : 'renomeadas'}. O nome precisa ser idêntico ao esperado, " \
          "com acentos e maiúsculas."
      else
        "#{uma ? 'Ela pode ter sido removida ou renomeada' : 'Elas podem ter sido removidas ou renomeadas'}. " \
          "Coluna a mais a planilha pode ter; coluna a menos, não."
      end

      "A aba \"#{sheet_name}\" está sem #{rotulo} #{lista(missing)}. " \
        "#{pista} Corrija o cabeçalho na planilha e envie o arquivo de novo."
    end

    def self.lista(headers)
      headers.map { |header| "\"#{header}\"" }
        .to_sentence(two_words_connector: " e ", last_word_connector: " e ")
    end

    def self.validate_mapa_headers!(actual)
      fixed = actual.grep_v(VOLUME_HEADER_PATTERN)
      check_headers!("Mapa de Clientes BIN", expected: MAPA_FIXED_HEADERS, actual: fixed)

      months_by_family = actual.filter_map { |header| VOLUME_HEADER_PATTERN.match(header) }
        .group_by { |match| match[1] }
        .transform_values { |matches| matches.map { |match| match[2] }.sort }
      return if months_by_family.keys.sort == VOLUME_FAMILIES.sort &&
        months_by_family.values.uniq.size == 1

      familias = months_by_family.map { |family, months| "#{family}: #{months.join(', ')}" }
      raise ArgumentError,
        "As colunas de volume mensal do Mapa não fecham entre si. As quatro famílias " \
        "(total, débito, crédito e antecipação) precisam trazer as mesmas competências, e " \
        "este arquivo traz #{familias.to_sentence}. Confira se algum mês ficou de fora de " \
        "uma das famílias na exportação."
    end

    # Cabeçalho de origem para cada campo de nome, respeitando a inversão por aba.
    def self.name_columns(sheet_name)
      return { legal_name: "NOME FANTASIA", trade_name: "RAZÃO SOCIAL" } if INVERTED_NAME_SHEETS.include?(sheet_name)

      { legal_name: "RAZÃO SOCIAL", trade_name: "NOME FANTASIA" }
    end

    def self.rule_for(sheet_name, header)
      return "invert_razao_fantasia" if INVERTED_NAME_SHEETS.include?(sheet_name) && NAME_HEADERS.include?(header)
      return "split_actions(>)" if header == "MELHOR CONVERSA"
      return "strip_non_digits" if [ "CNPJ", "CEP", "TELEFONE DO TRABALHO" ].include?(header)
      return "numeric_or_sentinel(Inativo)" if header == "NET MDR"
      return "iso_datetime" if [ "vip_boarding_date", "ULTIMO ACESSO NO APP" ].include?(header)
      return "excel_serial_date" if sheet_name != "Mapa de Clientes BIN" && header.start_with?("DATA")
      return "pt_br_date" if sheet_name == "Mapa de Clientes BIN" && header.start_with?("DATA")

      "identity"
    end
  end
end
