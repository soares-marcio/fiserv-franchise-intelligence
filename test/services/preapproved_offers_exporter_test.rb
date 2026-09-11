require "test_helper"
require "csv"
require "roo"

class PreapprovedOffersExporterTest < ActiveSupport::TestCase
  setup do
    @rows = [
      { "sub_channels" => "MIC ALFA", "cnpj" => "11222333000181",
        "legal_name" => "ALFA COMERCIO LTDA", "establishments" => 2,
        "preapproved_volume" => "350000.0", "preapproved_term" => 24,
        "preapproved_rate" => "3.28" },
      { "sub_channels" => "MIC GAMA", "cnpj" => "44555666000177",
        "legal_name" => "GAMA TRANSPORTES LTDA", "establishments" => 1,
        "preapproved_volume" => "120000.0", "preapproved_term" => nil,
        "preapproved_rate" => nil }
    ]
  end

  test "csv traz cabeçalho, uma linha por cliente e o total" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_equal PreapprovedOffersExporter::HEADERS, tabela.headers
    assert_equal [ "MIC ALFA", "MIC GAMA", "TOTAL" ], tabela.map { |linha| linha["MIC"] }
    # O CNPJ sai formatado, como na tela: o arquivo é lido por gente, não por máquina.
    assert_equal "11.222.333/0001-81", tabela[0]["CNPJ"]
    assert_equal "350000.0", tabela[0]["Volume pré-aprovado"]
    assert_equal "24", tabela[0]["Prazo pré-aprovado (meses)"]
    assert_equal "3.28", tabela[0]["Taxa pré-aprovada %"]
  end

  # A planilha traz prazo e taxa vazios em parte da carteira. Vazio continua vazio: zero seria
  # outra afirmação, e no Excel some do filtro "em branco".
  test "prazo e taxa ausentes ficam vazios, não zerados" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_nil tabela[1]["Prazo pré-aprovado (meses)"]
    assert_nil tabela[1]["Taxa pré-aprovada %"]
  end

  # Somar prazo de clientes diferentes não descreve oferta nenhuma, e a média tampouco: só
  # volume e contagem de ECs entram no total.
  test "o total soma o que é somável e deixa o resto em branco" do
    total = CSV.parse(exporter.to_csv, headers: true).find { |linha| linha["MIC"] == "TOTAL" }

    assert_equal "3", total["ECs no CNPJ"]
    assert_equal "470000.0", total["Volume pré-aprovado"]
    assert_nil total["Prazo pré-aprovado (meses)"]
    assert_nil total["Taxa pré-aprovada %"]
    assert_nil total["CNPJ"]
  end

  test "xlsx abre com a nota do recorte e as mesmas linhas do csv" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-clover.xlsx")
    File.binwrite(path, PreapprovedOffersExporter.new(@rows, sub_channel_name: "MIC ALFA").to_xlsx)
    aba = Roo::Excelx.new(path.to_s)

    assert_match(/MIC ALFA/, aba.row(1).first)
    assert_equal PreapprovedOffersExporter::HEADERS, aba.row(2)
    assert_equal "MIC ALFA", aba.row(3).first
    assert_equal "TOTAL", aba.row(5).first
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  # Sem MIC escolhido, a nota diz que o arquivo é da carteira inteira: aberto uma semana
  # depois, é ela que responde "isto era um recorte ou era tudo?".
  test "sem MIC escolhido, a nota do xlsx diz que são todas" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-clover.xlsx")
    File.binwrite(path, exporter.to_xlsx)

    assert_match(/todas as MICs/, Roo::Excelx.new(path.to_s).row(1).first)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  private

  def exporter
    PreapprovedOffersExporter.new(@rows)
  end
end
