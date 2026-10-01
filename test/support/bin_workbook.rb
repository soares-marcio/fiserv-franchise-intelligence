require "caxlsx"

# Gera planilhas BIN sintéticas com os cabeçalhos exatos do Template.
# Nenhum dado real de cliente entra no repositório, e os totais esperados
# saem dos próprios dados declarados aqui — nada é fixado à mão.
module BinWorkbook
  REPORT_ID = "9999"
  CHANNEL = "CANAL TESTE"
  PREVIOUS_PERIOD = Date.new(2026, 7, 1)
  CURRENT_PERIOD = Date.new(2026, 8, 1)
  MES_M1 = "202607"
  MES_ATUAL = "202608"
  # Volumes dos meses que não entram na reconciliação; distintos para não gerar empate.
  OUTROS_VOLUMES = { "202604" => 7, "202605" => 11, "202606" => 13 }.freeze

  Store = Struct.new(
    :ec, :cnpj, :sub_channel_name, :legal_name, :trade_name, :contract_status,
    :previous_days, :current_days, :best_conversation, :proposal,
    :accredited_on, :net_mdr, :app_access_at, :auto_boarding, :financial_solutions,
    :debits, :credits,
    :preapproved_volume, :preapproved_term, :preapproved_rate,
    :suspended_on, :proposal_status, :proposed_on,
    keyword_init: true
  ) do
    def total_m1 = previous_days.values.sum
    def total_atual = current_days.values.sum
    # Volume de uma competência AAAAMM na família pedida; 1 é o valor herdado dos
    # testes antigos, que não declaravam débito/crédito.
    def debit(month) = (debits || {}).fetch(month, 1)
    def credit(month) = (credits || {}).fetch(month, 1)
  end

  # EC 30000001 e 90000001 dividem o CNPJ de propósito: é o par que dispara
  # a anomalia ec_duplicate_candidate. A loja BETA não vende no mês atual.
  def self.default_stores
    [
      Store.new(
        ec: "30000001", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO DE ALIMENTOS LTDA", trade_name: "ALFA LANCHES",
        contract_status: "Active", previous_days: { 1 => 100, 2 => 200, 25 => 700 },
        current_days: { 1 => 150, 2 => 50, 10 => 300 },
        best_conversation: "Ligar > Enviar proposta", proposal: true
      ),
      Store.new(
        ec: "90000001", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO DE ALIMENTOS LTDA", trade_name: "ALFA EXPRESS",
        contract_status: "Active", previous_days: { 1 => 50 }, current_days: { 1 => 10, 2 => 20 },
        best_conversation: nil, proposal: false
      ),
      Store.new(
        ec: "30000002", cnpj: "44555666000172", sub_channel_name: "MIC BETA",
        legal_name: "BETA SERVICOS LTDA", trade_name: "BETA CAFE",
        contract_status: "Suspended", previous_days: { 1 => 400 }, current_days: {},
        best_conversation: nil, proposal: false
      )
    ]
  end

  # Dia de corte observado: maior dia com movimento no mês atual.
  def self.cutoff_day(stores = default_stores)
    stores.flat_map { |store| store.current_days.keys }.max || 1
  end

  # volume_months permite simular a virada da planilha (um mês novo por ciclo), que é o
  # regime real de operação; o padrão preserva os totais dos testes existentes.
  def self.write(path, stores: default_stores, volume_months: BinImport::Template::DEFAULT_VOLUME_MONTHS,
    channel: CHANNEL, report_id: REPORT_ID)
    Axlsx::Package.new do |package|
      sheet_rows(stores, volume_months:, channel:, report_id:).each do |sheet_name, rows|
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

  def self.sheet_rows(stores, volume_months: BinImport::Template::DEFAULT_VOLUME_MONTHS, channel: CHANNEL,
    report_id: REPORT_ID)
    {
      "Faturamento" => stores.map { |store| revenue_row(store, channel:) },
      "Ativacao" => stores.select(&:proposal).map { |store| activation_row(store, channel:) },
      "Mapa de Clientes BIN" => stores.map { |store| map_row(store, volume_months:, channel:, report_id:) }
    }
  end

  # Mapa vem com os cabeçalhos de nome corretos.
  def self.map_row(store, volume_months: BinImport::Template::DEFAULT_VOLUME_MONTHS, channel: CHANNEL,
    report_id: REPORT_ID)
    {
      "REPORT_ID" => report_id, "HIERARQUIA" => channel, "CANAL" => channel,
      "SUB-CANAL" => store.sub_channel_name, "EC" => store.ec, "CNPJ" => store.cnpj,
      "TIPO DE PESSOA" => "PJ", "RAZÃO SOCIAL" => store.legal_name,
      "NOME FANTASIA" => store.trade_name, "STATUS DO CONTRATO" => store.contract_status,
      "MELHOR CONVERSA" => store.best_conversation, "CIDADE" => "GOIANIA", "ESTADO" => "GO",
      "CEP" => "74000000", "TELEFONE DO TRABALHO" => "6230000000",
      "DATA DE CREDENCIAMENTO" => store.accredited_on || "01/02/2026",
      "DATA DE ATIVAÇÃO" => "05/02/2026",
      "DATA DE SUSPENSÃO" => store.suspended_on,
      # A planilha real marca quem transacionou no mês; aqui é o que os dias declarados dizem.
      "ATIVO NO MÊS ATUAL?" => store.current_days.any? ? "SIM" : "NÃO",
      "NET MDR" => store.net_mdr, "ULTIMO ACESSO NO APP" => store.app_access_at,
      "STATUS ANTECIP AUTO NO BOARDING" => store.auto_boarding,
      "SOLUÇÕES FINANCEIRAS" => store.financial_solutions,
      # A oferta pré-aprovada do Clover Capital. PARCELA_PRE_APROVADA fica de fora de
      # propósito: no arquivo real ela é a única das quatro que nunca traz valor, e a
      # planilha sintética existe para reproduzir o arquivo, não para melhorá-lo.
      "VOLUME_PRE_APROVADO" => store.preapproved_volume,
      "PRAZO_PRE_APROVADO" => store.preapproved_term,
      "TAXA_PRE_APROVADA" => store.preapproved_rate
    }.merge(volume_columns(store, volume_months))
  end

  # Faturamento e Ativacao vêm com razão social e nome fantasia trocados na origem.
  def self.revenue_row(store, channel: CHANNEL)
    days = (1..31).to_h do |day|
      [ format("DIA %02d", day), store.current_days.fetch(day, 0) ]
    end.merge((1..31).to_h do |day|
      [ format("DIA %02d_M_1", day), store.previous_days.fetch(day, 0) ]
    end)
    {
      "HIERARQUIA" => channel, "CANAL" => channel, "SUB-CANAL" => store.sub_channel_name,
      "EC" => store.ec, "CNPJ" => store.cnpj,
      "RAZÃO SOCIAL" => store.trade_name, "NOME FANTASIA" => store.legal_name,
      "STATUS DO CONTRATO" => store.contract_status, "CIDADE" => "GOIANIA", "ESTADO" => "GO",
      "CEP" => "74000000", "TELEFONE DO TRABALHO" => "6230000000",
      "fat_total_m1" => store.total_m1, "FATURAMENTO TOTAL DESTE MÊS" => store.total_atual
    }.merge(days)
  end

  def self.activation_row(store, channel: CHANNEL)
    {
      "HIERARQUIA" => channel, "CANAL" => channel, "SUB-CANAL" => store.sub_channel_name,
      "NR DA PROPOSTA" => "P#{store.ec}", "DATA DA PROPOSTA" => store.proposed_on || "2026-01-10",
      "EC" => store.ec, "CNPJ" => store.cnpj,
      "RAZÃO SOCIAL" => store.trade_name, "NOME FANTASIA" => store.legal_name,
      # Vocabulário real da coluna: "Boarded to BWA", "Credit Declined" e "Pending QC".
      "STATUS DA PROPOSTA" => store.proposal_status || "Boarded to BWA",
      "DATA DE ATIVAÇÃO" => "2026-02-05",
      "TICKET MÉDIO" => 120, "FATURAMENTO ANUAL PREVISTO" => 90_000
    }
  end

  def self.volume_columns(store, volume_months = BinImport::Template::DEFAULT_VOLUME_MONTHS)
    totals = OUTROS_VOLUMES.merge(MES_M1 => store.total_m1, MES_ATUAL => store.total_atual)
    BinImport::Template::VOLUME_FAMILIES.flat_map do |family|
      volume_months.map do |month|
        value = case family
        when "VOLUME DE FATURAMENTO TOTAL" then totals.fetch(month, 5)
        when "VOLUME DE FATURAMENTO DÉBITO" then store.debit(month)
        when "VOLUME DE FATURAMENTO CRÉDITO" then store.credit(month)
        else 1
        end
        [ "#{family} #{month}", value ]
      end
    end.to_h
  end

  # Lojas para os testes da página 3M: janelas de credenciamento, MDR e volumes de
  # débito/crédito deliberados para cobrir acelerador, redutor e as hipóteses de
  # antecipação. Não altera default_lojas, usado pelos testes existentes.
  def self.earnings_stores
    [
      # Credenciada em julho: M0 fechado, M1 aberto (cortado), M2 sem cobertura.
      # Com app e antecipação declarada; MDR alto puxa a carteira GAMA para a faixa topo.
      Store.new(
        ec: "50000001", cnpj: "22333444000155", sub_channel_name: "MIC GAMA",
        legal_name: "GAMA COMERCIO LTDA", trade_name: "GAMA STORE",
        contract_status: "Active", previous_days: { 5 => 18_000 }, current_days: { 3 => 55_000 },
        best_conversation: nil, proposal: false,
        accredited_on: Date.new(2026, 7, 10), net_mdr: 0.42,
        app_access_at: "2026-07-15 10:00", auto_boarding: "SIM",
        financial_solutions: "Auto",
        debits: { "202606" => 1_000, "202607" => 4_000, "202608" => 9_000 },
        credits: { "202606" => 1_000, "202607" => 6_000, "202608" => 12_000 }
      ),
      # Sem MDR ("Inativo"): sai da média ponderada. Crescimento forte na GAMA vem daqui.
      Store.new(
        ec: "50000002", cnpj: "33444555000166", sub_channel_name: "MIC GAMA",
        legal_name: "GAMA FILIAL LTDA", trade_name: "GAMA ANEXO",
        contract_status: "Active", previous_days: { 2 => 500 }, current_days: { 2 => 800 },
        best_conversation: nil, proposal: false,
        net_mdr: "Inativo",
        debits: { "202606" => 500, "202607" => 500, "202608" => 3_000 },
        credits: { "202606" => 500, "202607" => 500, "202608" => 2_000 }
      ),
      # Carteira DELTA em queda de mais de 50% na última transição; MDR mediano;
      # credenciamento antigo, fora do histórico coberto — "não apurável", nunca R$0.
      Store.new(
        ec: "50000003", cnpj: "44555666000177", sub_channel_name: "MIC DELTA",
        legal_name: "DELTA SERVICOS LTDA", trade_name: "DELTA LOJA",
        contract_status: "Active", previous_days: { 1 => 9_000 }, current_days: { 1 => 2_000 },
        best_conversation: nil, proposal: false,
        accredited_on: Date.new(2026, 2, 1), net_mdr: 0.31,
        financial_solutions: "NÃO",
        debits: { "202606" => 5_000, "202607" => 10_000, "202608" => 2_000 },
        credits: { "202606" => 5_000, "202607" => 10_000, "202608" => 2_000 }
      )
    ]
  end

  # Lojas para a campanha APP (digitalização): por CNPJ, no mês do primeiro acesso ao app,
  # dentro de M0–M2. O primeiro arquivo (acessos: false) mostra os CNPJs ainda sem acesso e o
  # segundo traz o acesso — é essa transição que prova o mês do primeiro acesso. O último
  # CNPJ já acessa no primeiro arquivo: sem transição, a campanha cai em M0.
  def self.app_campaign_stores(accesses: true)
    access = ->(data) { data if accesses }
    [
      # CNPJ com dois ECs credenciados em julho e acesso em agosto (M1): paga uma vez, no
      # EC credenciado primeiro.
      app_store("72000001", "71111222000100", accredited_on: Date.new(2026, 7, 10),
        app_access_at: access.("2026-08-05 09:00")),
      app_store("72000002", "71111222000100", accredited_on: Date.new(2026, 7, 20),
        app_access_at: access.("2026-08-05 09:00")),
      # Credenciado em abril, acesso em agosto (M4): fora da janela, não paga.
      app_store("72000003", "72222333000100", accredited_on: Date.new(2026, 4, 2),
        app_access_at: access.("2026-08-01 10:00")),
      # Credenciado em agosto, sem acesso ao app: não paga.
      app_store("72000004", "73333444000100", accredited_on: Date.new(2026, 8, 3)),
      # Credenciado em junho, acesso em agosto (M2): paga em agosto.
      app_store("72000005", "74444555000100", accredited_on: Date.new(2026, 6, 15),
        app_access_at: access.("2026-08-20 15:00")),
      # Credenciado em julho, já com acesso no primeiro arquivo: o primeiro acesso pode ser
      # anterior a tudo que foi importado, e a campanha cai em M0.
      app_store("72000006", "75555666000100", accredited_on: Date.new(2026, 7, 5),
        app_access_at: "2026-08-03 11:00")
    ]
  end

  def self.app_store(ec, cnpj, accredited_on:, app_access_at: nil)
    Store.new(
      ec:, cnpj:, sub_channel_name: "MIC THETA", legal_name: "LOJA #{ec} LTDA",
      # Totais distintos entre os dois meses: iguais, o importador não descobre qual coluna
      # de volume é a do mês atual.
      trade_name: "LOJA #{ec}", contract_status: "Active", previous_days: { 1 => 100 },
      current_days: { 1 => 200 }, best_conversation: nil, proposal: false,
      accredited_on:, app_access_at:, financial_solutions: "NÃO"
    )
  end

  # Lojas para os Indicadores do Anexo B, em duas carteiras: KAPPA reprova em tudo no mês
  # atual e SIGMA cumpre tudo. Os percentuais esperados saem destas declarações.
  def self.indicator_stores
    kappa = [
      # Três credenciadas no mês atual (menos de 5: Risco). Só a primeira passa de R$ 10.000
      # em débito + crédito; a terceira não vende. Uma proposta de cada status.
      indicator_store("61000001", "MIC KAPPA", accredited_on: Date.new(2026, 8, 3),
        current_days: { 4 => 6_000 }, debits: { "202608" => 6_000 }, credits: { "202608" => 5_000 }),
      indicator_store("61000002", "MIC KAPPA", accredited_on: Date.new(2026, 8, 12),
        current_days: { 2 => 300 }, proposal_status: "Credit Declined"),
      indicator_store("61000003", "MIC KAPPA", accredited_on: Date.new(2026, 8, 20),
        current_days: {}, proposal_status: "Pending QC"),
      # Credenciada em junho e suspensa no mês atual: fica na base e conta como descredenciada.
      indicator_store("61000004", "MIC KAPPA", accredited_on: Date.new(2026, 6, 15),
        suspended_on: Date.new(2026, 8, 20), current_days: {}, proposed_on: Date.new(2026, 6, 1)),
      # Suspensa no mês anterior: fora da base do mês atual.
      indicator_store("61000005", "MIC KAPPA", accredited_on: Date.new(2026, 5, 2),
        suspended_on: Date.new(2026, 7, 5), current_days: {}, proposal: false)
    ]
    sigma = (1..10).map do |n|
      indicator_store(format("62%06d", n), "MIC SIGMA", accredited_on: Date.new(2026, 8, n),
        current_days: { n => 12_000 }, debits: { "202608" => 7_000 }, credits: { "202608" => 5_000 })
    end
    kappa + sigma
  end

  def self.indicator_store(ec, sub_channel_name, current_days:, proposal: true,
    proposed_on: Date.new(2026, 8, 1), **attributes)
    Store.new(
      ec:, cnpj: "#{ec}000199", sub_channel_name:,
      legal_name: "LOJA #{ec} LTDA", trade_name: "LOJA #{ec}",
      contract_status: "Active", previous_days: {}, current_days:, best_conversation: nil, proposal:,
      proposed_on:, **attributes
    )
  end
end
