require "caxlsx"

# Gera planilhas BIN sintéticas com os cabeçalhos exatos do Template.
# Nenhum dado real de cliente entra no repositório, e os totais esperados
# saem dos próprios dados declarados aqui — nada é fixado à mão.
module BinWorkbook
  REPORT_ID = "9999"
  CANAL = "CANAL TESTE"
  COMPETENCIA_M1 = Date.new(2026, 7, 1)
  COMPETENCIA_ATUAL = Date.new(2026, 8, 1)
  MES_M1 = "202607"
  MES_ATUAL = "202608"
  # Volumes dos meses que não entram na reconciliação; distintos para não gerar empate.
  OUTROS_VOLUMES = { "202604" => 7, "202605" => 11, "202606" => 13 }.freeze

  Loja = Struct.new(
    :ec, :cnpj, :sub_canal, :razao_social, :nome_fantasia, :status_contrato,
    :dias_m1, :dias_atual, :melhor_conversa, :proposta,
    keyword_init: true
  ) do
    def total_m1 = dias_m1.values.sum
    def total_atual = dias_atual.values.sum
  end

  # EC 30000001 e 90000001 dividem o CNPJ de propósito: é o par que dispara
  # a anomalia ec_duplicate_candidate. A loja BETA não vende no mês atual.
  def self.default_lojas
    [
      Loja.new(
        ec: "30000001", cnpj: "11222333000181", sub_canal: "MIC ALFA",
        razao_social: "ALFA COMERCIO DE ALIMENTOS LTDA", nome_fantasia: "ALFA LANCHES",
        status_contrato: "Active", dias_m1: { 1 => 100, 2 => 200, 25 => 700 },
        dias_atual: { 1 => 150, 2 => 50, 10 => 300 },
        melhor_conversa: "Ligar > Enviar proposta", proposta: true
      ),
      Loja.new(
        ec: "90000001", cnpj: "11222333000181", sub_canal: "MIC ALFA",
        razao_social: "ALFA COMERCIO DE ALIMENTOS LTDA", nome_fantasia: "ALFA EXPRESS",
        status_contrato: "Active", dias_m1: { 1 => 50 }, dias_atual: { 1 => 10, 2 => 20 },
        melhor_conversa: nil, proposta: false
      ),
      Loja.new(
        ec: "30000002", cnpj: "44555666000172", sub_canal: "MIC BETA",
        razao_social: "BETA SERVICOS LTDA", nome_fantasia: "BETA CAFE",
        status_contrato: "Suspended", dias_m1: { 1 => 400 }, dias_atual: {},
        melhor_conversa: nil, proposta: false
      )
    ]
  end

  # Dia de corte observado: maior dia com movimento no mês atual.
  def self.cutoff_day(lojas = default_lojas)
    lojas.flat_map { |loja| loja.dias_atual.keys }.max || 1
  end

  def self.write(path, lojas: default_lojas)
    Axlsx::Package.new do |package|
      sheet_rows(lojas).each do |sheet_name, rows|
        headers = BinImport::Template::EXPECTED_HEADERS.fetch(sheet_name)
        package.workbook.add_worksheet(name: sheet_name) do |worksheet|
          worksheet.add_row headers
          rows.each { |row| worksheet.add_row headers.map { |header| row[header] } }
        end
      end
      package.serialize(path.to_s)
    end
    path
  end

  def self.sheet_rows(lojas)
    {
      "Faturamento" => lojas.map { |loja| faturamento_row(loja) },
      "Ativacao" => lojas.select(&:proposta).map { |loja| ativacao_row(loja) },
      "Mapa de Clientes BIN" => lojas.map { |loja| mapa_row(loja) }
    }
  end

  # Mapa vem com os cabeçalhos de nome corretos.
  def self.mapa_row(loja)
    {
      "REPORT_ID" => REPORT_ID, "HIERARQUIA" => CANAL, "CANAL" => CANAL,
      "SUB-CANAL" => loja.sub_canal, "EC" => loja.ec, "CNPJ" => loja.cnpj,
      "TIPO DE PESSOA" => "PJ", "RAZÃO SOCIAL" => loja.razao_social,
      "NOME FANTASIA" => loja.nome_fantasia, "STATUS DO CONTRATO" => loja.status_contrato,
      "MELHOR CONVERSA" => loja.melhor_conversa, "CIDADE" => "GOIANIA", "ESTADO" => "GO",
      "CEP" => "74000000", "TELEFONE DO TRABALHO" => "6230000000",
      "DATA DE CREDENCIAMENTO" => "01/02/2026", "DATA DE ATIVAÇÃO" => "05/02/2026"
    }.merge(volume_columns(loja))
  end

  # Faturamento e Ativacao vêm com razão social e nome fantasia trocados na origem.
  def self.faturamento_row(loja)
    dias = (1..31).to_h do |day|
      [ format("DIA %02d", day), loja.dias_atual.fetch(day, 0) ]
    end.merge((1..31).to_h do |day|
      [ format("DIA %02d_M_1", day), loja.dias_m1.fetch(day, 0) ]
    end)
    {
      "HIERARQUIA" => CANAL, "CANAL" => CANAL, "SUB-CANAL" => loja.sub_canal,
      "EC" => loja.ec, "CNPJ" => loja.cnpj,
      "RAZÃO SOCIAL" => loja.nome_fantasia, "NOME FANTASIA" => loja.razao_social,
      "STATUS DO CONTRATO" => loja.status_contrato, "CIDADE" => "GOIANIA", "ESTADO" => "GO",
      "CEP" => "74000000", "TELEFONE DO TRABALHO" => "6230000000",
      "fat_total_m1" => loja.total_m1, "FATURAMENTO TOTAL DESTE MÊS" => loja.total_atual
    }.merge(dias)
  end

  def self.ativacao_row(loja)
    {
      "HIERARQUIA" => CANAL, "CANAL" => CANAL, "SUB-CANAL" => loja.sub_canal,
      "NR DA PROPOSTA" => "P#{loja.ec}", "DATA DA PROPOSTA" => "2026-01-10",
      "EC" => loja.ec, "CNPJ" => loja.cnpj,
      "RAZÃO SOCIAL" => loja.nome_fantasia, "NOME FANTASIA" => loja.razao_social,
      "STATUS DA PROPOSTA" => "Aprovada", "DATA DE ATIVAÇÃO" => "2026-02-05",
      "TICKET MÉDIO" => 120, "FATURAMENTO ANUAL PREVISTO" => 90_000
    }
  end

  def self.volume_columns(loja)
    totais = OUTROS_VOLUMES.merge(MES_M1 => loja.total_m1, MES_ATUAL => loja.total_atual)
    BinImport::Template::VOLUME_FAMILIES.flat_map do |family|
      BinImport::Template::VOLUME_MONTHS.map do |month|
        value = family == "VOLUME DE FATURAMENTO TOTAL" ? totais.fetch(month) : 1
        [ "#{family} #{month}", value ]
      end
    end.to_h
  end
end
