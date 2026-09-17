require "test_helper"
require "csv"
require "roo"

class ThreeMonthEarningsExporterTest < ActiveSupport::TestCase
  setup do
    @window = [ Date.new(2026, 6, 1), Date.new(2026, 7, 1), Date.new(2026, 8, 1) ]
    @reports = [
      { name: "MIC ALFA",
        prize: { accredited: 3, digitalization: 90.to_d, addon_without_auto: 150.to_d,
                 addon_with_auto: 260.to_d, addon_amount: 260.to_d, undefined_modality: 0 },
        months: [
          { period: @window[0], debit: 1000.to_d, credit: 2000.to_d, total: 3000.to_d,
            covered: true, partial: false },
          { period: @window[1], debit: 0.to_d, credit: 0.to_d, total: 0.to_d,
            covered: false, partial: false },
          { period: @window[2], debit: 500.to_d, credit: 700.to_d, total: 1200.to_d,
            covered: true, partial: true }
        ] }
    ]
  end

  test "uma linha por MIC, com os três meses em colunas rotuladas M0, M1 e M2" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_equal "MIC", tabela.headers.first
    inicio = tabela.headers.index("M0 Débito")
    assert_equal %w[M0\ Débito M0\ Crédito M0\ Total], tabela.headers[inicio, 3],
      "os três meses saem em colunas consecutivas, rotuladas pelo índice na janela"
    assert_equal 1, tabela.size
    assert_equal "3000.0", tabela[0]["M0 Total"]
  end

  # Mês sem cobertura sai vazio, e não zerado: "não sabemos" não é "não faturou" — a mesma
  # distinção que a tela faz com o travessão.
  test "mês sem cobertura fica em branco" do
    linha = CSV.parse(exporter.to_csv, headers: true).first

    assert_nil linha["M1 Débito"]
    assert_nil linha["M1 Total"]
    assert_equal "1200.0", linha["M2 Total"]
  end

  # O adicional sai resolvido pela modalidade contratada (Anexo C). As duas hipóteses seguem
  # no fim do arquivo, como na view: é contra elas que o valor resolvido se confere.
  test "o prêmio sai resolvido, com as duas hipóteses no fim para conferência" do
    linha = CSV.parse(exporter.to_csv, headers: true).first

    assert_equal "3", linha["ECs no M0"]
    assert_equal "90.0", linha["Digitalização"]
    assert_equal "260.0", linha["Adicional por faturamento"]
    assert_equal "350.0", linha["Prêmio de entrada"], "digitalização mais o adicional resolvido"
    assert_equal "0", linha["ECs sem modalidade"]
    assert_equal "150.0", linha["Adicional sem auto/flex"]
    assert_equal "260.0", linha["Adicional com auto/flex"]
  end

  test "a janela fica escrita na nota do xlsx: M0 sozinho não diz de quando é o arquivo" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-3m.xlsx")
    File.binwrite(path, exporter.to_xlsx)

    assert_match(/06\/2026 · 07\/2026 · 08\/2026/, Roo::Excelx.new(path.to_s).row(1).first)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  private

  def exporter
    ThreeMonthEarningsExporter.new(@reports, window: @window)
  end
end
