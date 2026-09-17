require "test_helper"
require "csv"

class RecurringEarningsExporterTest < ActiveSupport::TestCase
  setup do
    @reports = [
      { name: "MIC ALFA", months: [
        { period: Date.new(2026, 7, 1), debit: 1000.to_d, credit: 2000.to_d, net_mdr: 1.5,
          mdr_source: "closed", partial: false, recurring: 30.to_d, accreditation: 0.to_d,
          accelerator: 0.to_d, reducer: 0.to_d },
        { period: Date.new(2026, 8, 1), debit: 500.to_d, credit: 500.to_d, net_mdr: nil,
          mdr_source: "fallback", partial: true, recurring: 10.to_d, accreditation: 89.to_d,
          accelerator: 5.to_d, reducer: 0.to_d }
      ] }
    ]
  end

  test "uma linha por MIC e competência, na ordem da série" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_equal RecurringEarningsExporter::HEADERS, tabela.headers
    assert_equal [ "07/2026", "08/2026", nil ], tabela.map { |linha| linha["Competência"] }
    assert_equal [ "MIC ALFA", "MIC ALFA", "TOTAL" ], tabela.map { |linha| linha["MIC"] }
  end

  # A tela mostra travessão onde não há ajuste e † onde o Net MDR veio de outro arquivo. O
  # arquivo diz as duas coisas sem inventar número: célula vazia e a origem em texto.
  test "ajuste zerado e Net MDR ausente saem vazios, com a origem marcada" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_nil tabela[0]["Ajuste"]
    assert_equal "1.5", tabela[0]["Net MDR %"]
    assert_nil tabela[0]["Origem do Net MDR"]
    assert_nil tabela[1]["Net MDR %"]
    assert_equal "arquivo anterior", tabela[1]["Origem do Net MDR"]
    assert_equal "sim", tabela[1]["Competência parcial"]
  end

  # A Participação do mês é repasse + credenciamento + ajuste (Anexo C, item 1). A parcela
  # aparece na coluna própria porque é ela que entra na base do redutor.
  test "a participação do mês soma repasse, credenciamento e ajuste, e o total fecha" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_nil tabela[0]["Credenciamento"], "sem parcela, célula vazia e não zero"
    assert_equal "30.0", tabela[0]["Participação do mês"]
    assert_equal "89.0", tabela[1]["Credenciamento"]
    assert_equal "104.0", tabela[1]["Participação do mês"],
      "10 de repasse, 89 de credenciamento e 5 de acelerador"
    assert_equal "134.0", tabela[2]["Participação do mês"]
    assert_equal "40.0", tabela[2]["Repasse"]
    assert_equal "89.0", tabela[2]["Credenciamento"]
  end

  private

  def exporter
    RecurringEarningsExporter.new(@reports)
  end
end
