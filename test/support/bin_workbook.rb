require "caxlsx"

# Gera planilhas BIN sintéticas com os cabeçalhos exatos do Template.
# Nenhum dado real de cliente entra no repositório, e os totais esperados
# saem dos próprios dados declarados aqui — nada é fixado à mão.
module BinWorkbook
  REPORT_ID = "9999"
  CANAL = "CANAL TESTE"
  PREVIOUS_PERIOD = Date.new(2026, 7, 1)
  CURRENT_PERIOD = Date.new(2026, 8, 1)
  MES_M1 = "202607"
  MES_ATUAL = "202608"
  # Volumes dos meses que não entram na reconciliação; distintos para não gerar empate.
  OUTROS_VOLUMES = { "202604" => 7, "202605" => 11, "202606" => 13 }.freeze

  Loja = Struct.new(
    :ec, :cnpj, :sub_channel_name, :legal_name, :trade_name, :contract_status,
    :dias_m1, :dias_atual, :melhor_conversa, :proposta,
    :accredited_on, :net_mdr, :app_access_at, :auto_boarding, :debitos, :creditos,
    keyword_init: true
  ) do
    def total_m1 = dias_m1.values.sum
    def total_atual = dias_atual.values.sum
    # Volume de uma competência AAAAMM na família pedida; 1 é o valor herdado dos
    # testes antigos, que não declaravam débito/crédito.
    def debito(month) = (debitos || {}).fetch(month, 1)
    def credito(month) = (creditos || {}).fetch(month, 1)
  end

  # EC 30000001 e 90000001 dividem o CNPJ de propósito: é o par que dispara
  # a anomalia ec_duplicate_candidate. A loja BETA não vende no mês atual.
  def self.default_lojas
    [
      Loja.new(
        ec: "30000001", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO DE ALIMENTOS LTDA", trade_name: "ALFA LANCHES",
        contract_status: "Active", dias_m1: { 1 => 100, 2 => 200, 25 => 700 },
        dias_atual: { 1 => 150, 2 => 50, 10 => 300 },
        melhor_conversa: "Ligar > Enviar proposta", proposta: true
      ),
      Loja.new(
        ec: "90000001", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO DE ALIMENTOS LTDA", trade_name: "ALFA EXPRESS",
        contract_status: "Active", dias_m1: { 1 => 50 }, dias_atual: { 1 => 10, 2 => 20 },
        melhor_conversa: nil, proposta: false
      ),
      Loja.new(
        ec: "30000002", cnpj: "44555666000172", sub_channel_name: "MIC BETA",
        legal_name: "BETA SERVICOS LTDA", trade_name: "BETA CAFE",
        contract_status: "Suspended", dias_m1: { 1 => 400 }, dias_atual: {},
        melhor_conversa: nil, proposta: false
      )
    ]
  end

  # Dia de corte observado: maior dia com movimento no mês atual.
  def self.cutoff_day(lojas = default_lojas)
    lojas.flat_map { |loja| loja.dias_atual.keys }.max || 1
  end

  # volume_months permite simular a virada da planilha (um mês novo por ciclo), que é o
  # regime real de operação; o padrão preserva os totais dos testes existentes.
  def self.write(path, lojas: default_lojas, volume_months: BinImport::Template::DEFAULT_VOLUME_MONTHS)
    Axlsx::Package.new do |package|
      sheet_rows(lojas, volume_months:).each do |sheet_name, rows|
        headers = headers_for(sheet_name, volume_months)
        package.workbook.add_worksheet(name: sheet_name) do |worksheet|
          worksheet.add_row headers
          rows.each { |row| worksheet.add_row headers.map { |header| row[header] } }
        end
      end
      package.serialize(path.to_s)
    end
    path
  end

  def self.headers_for(sheet_name, volume_months)
    return BinImport::Template::EXPECTED_HEADERS.fetch(sheet_name) unless sheet_name == "Mapa de Clientes BIN"

    [
      *BinImport::Template::MAPA_BASE,
      *BinImport::Template::VOLUME_FAMILIES.flat_map { |family| volume_months.map { |month| "#{family} #{month}" } },
      "agenda_semanal"
    ]
  end

  def self.sheet_rows(lojas, volume_months: BinImport::Template::DEFAULT_VOLUME_MONTHS)
    {
      "Faturamento" => lojas.map { |loja| faturamento_row(loja) },
      "Ativacao" => lojas.select(&:proposta).map { |loja| ativacao_row(loja) },
      "Mapa de Clientes BIN" => lojas.map { |loja| mapa_row(loja, volume_months:) }
    }
  end

  # Mapa vem com os cabeçalhos de nome corretos.
  def self.mapa_row(loja, volume_months: BinImport::Template::DEFAULT_VOLUME_MONTHS)
    {
      "REPORT_ID" => REPORT_ID, "HIERARQUIA" => CANAL, "CANAL" => CANAL,
      "SUB-CANAL" => loja.sub_channel_name, "EC" => loja.ec, "CNPJ" => loja.cnpj,
      "TIPO DE PESSOA" => "PJ", "RAZÃO SOCIAL" => loja.legal_name,
      "NOME FANTASIA" => loja.trade_name, "STATUS DO CONTRATO" => loja.contract_status,
      "MELHOR CONVERSA" => loja.melhor_conversa, "CIDADE" => "GOIANIA", "ESTADO" => "GO",
      "CEP" => "74000000", "TELEFONE DO TRABALHO" => "6230000000",
      "DATA DE CREDENCIAMENTO" => loja.accredited_on || "01/02/2026",
      "DATA DE ATIVAÇÃO" => "05/02/2026",
      "NET MDR" => loja.net_mdr, "ULTIMO ACESSO NO APP" => loja.app_access_at,
      "STATUS ANTECIP AUTO NO BOARDING" => loja.auto_boarding
    }.merge(volume_columns(loja, volume_months))
  end

  # Faturamento e Ativacao vêm com razão social e nome fantasia trocados na origem.
  def self.faturamento_row(loja)
    dias = (1..31).to_h do |day|
      [ format("DIA %02d", day), loja.dias_atual.fetch(day, 0) ]
    end.merge((1..31).to_h do |day|
      [ format("DIA %02d_M_1", day), loja.dias_m1.fetch(day, 0) ]
    end)
    {
      "HIERARQUIA" => CANAL, "CANAL" => CANAL, "SUB-CANAL" => loja.sub_channel_name,
      "EC" => loja.ec, "CNPJ" => loja.cnpj,
      "RAZÃO SOCIAL" => loja.trade_name, "NOME FANTASIA" => loja.legal_name,
      "STATUS DO CONTRATO" => loja.contract_status, "CIDADE" => "GOIANIA", "ESTADO" => "GO",
      "CEP" => "74000000", "TELEFONE DO TRABALHO" => "6230000000",
      "fat_total_m1" => loja.total_m1, "FATURAMENTO TOTAL DESTE MÊS" => loja.total_atual
    }.merge(dias)
  end

  def self.ativacao_row(loja)
    {
      "HIERARQUIA" => CANAL, "CANAL" => CANAL, "SUB-CANAL" => loja.sub_channel_name,
      "NR DA PROPOSTA" => "P#{loja.ec}", "DATA DA PROPOSTA" => "2026-01-10",
      "EC" => loja.ec, "CNPJ" => loja.cnpj,
      "RAZÃO SOCIAL" => loja.trade_name, "NOME FANTASIA" => loja.legal_name,
      "STATUS DA PROPOSTA" => "Aprovada", "DATA DE ATIVAÇÃO" => "2026-02-05",
      "TICKET MÉDIO" => 120, "FATURAMENTO ANUAL PREVISTO" => 90_000
    }
  end

  def self.volume_columns(loja, volume_months = BinImport::Template::DEFAULT_VOLUME_MONTHS)
    totais = OUTROS_VOLUMES.merge(MES_M1 => loja.total_m1, MES_ATUAL => loja.total_atual)
    BinImport::Template::VOLUME_FAMILIES.flat_map do |family|
      volume_months.map do |month|
        value = case family
        when "VOLUME DE FATURAMENTO TOTAL" then totais.fetch(month, 5)
        when "VOLUME DE FATURAMENTO DÉBITO" then loja.debito(month)
        when "VOLUME DE FATURAMENTO CRÉDITO" then loja.credito(month)
        else 1
        end
        [ "#{family} #{month}", value ]
      end
    end.to_h
  end

  # Lojas para os testes da página 3M: janelas de credenciamento, MDR e volumes de
  # débito/crédito deliberados para cobrir acelerador, redutor e as hipóteses de
  # antecipação. Não altera default_lojas, usado pelos testes existentes.
  def self.earnings_lojas
    [
      # Credenciada em julho: M0 fechado, M1 aberto (cortado), M2 sem cobertura.
      # Com app e antecipação declarada; MDR alto puxa a carteira GAMA para a faixa topo.
      Loja.new(
        ec: "50000001", cnpj: "22333444000155", sub_channel_name: "MIC GAMA",
        legal_name: "GAMA COMERCIO LTDA", trade_name: "GAMA STORE",
        contract_status: "Active", dias_m1: { 5 => 18_000 }, dias_atual: { 3 => 55_000 },
        melhor_conversa: nil, proposta: false,
        accredited_on: Date.new(2026, 7, 10), net_mdr: 0.42,
        app_access_at: "2026-07-15 10:00", auto_boarding: "SIM",
        debitos: { "202606" => 1_000, "202607" => 4_000, "202608" => 9_000 },
        creditos: { "202606" => 1_000, "202607" => 6_000, "202608" => 12_000 }
      ),
      # Sem MDR ("Inativo"): sai da média ponderada. Crescimento forte na GAMA vem daqui.
      Loja.new(
        ec: "50000002", cnpj: "33444555000166", sub_channel_name: "MIC GAMA",
        legal_name: "GAMA FILIAL LTDA", trade_name: "GAMA ANEXO",
        contract_status: "Active", dias_m1: { 2 => 500 }, dias_atual: { 2 => 800 },
        melhor_conversa: nil, proposta: false,
        net_mdr: "Inativo",
        debitos: { "202606" => 500, "202607" => 500, "202608" => 3_000 },
        creditos: { "202606" => 500, "202607" => 500, "202608" => 2_000 }
      ),
      # Carteira DELTA em queda de mais de 50% na última transição; MDR mediano;
      # credenciamento antigo, fora do histórico coberto — "não apurável", nunca R$0.
      Loja.new(
        ec: "50000003", cnpj: "44555666000177", sub_channel_name: "MIC DELTA",
        legal_name: "DELTA SERVICOS LTDA", trade_name: "DELTA LOJA",
        contract_status: "Active", dias_m1: { 1 => 9_000 }, dias_atual: { 1 => 2_000 },
        melhor_conversa: nil, proposta: false,
        accredited_on: Date.new(2026, 2, 1), net_mdr: 0.31,
        debitos: { "202606" => 5_000, "202607" => 10_000, "202608" => 2_000 },
        creditos: { "202606" => 5_000, "202607" => 10_000, "202608" => 2_000 }
      )
    ]
  end
end
