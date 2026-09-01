require "test_helper"

# As competências de volume avançam a cada planilha semanal. Este arquivo cobre a virada
# de mês — o cenário que, com a lista fixa antiga, derrubava o import inteiro com
# "Cabeçalhos divergentes" — e as malformações que continuam proibidas.
class TemplateVolumeMonthsTest < ActiveSupport::TestCase
  SHIFTED_MONTHS = %w[202605 202606 202607 202608 202609].freeze

  test "a planilha da virada de mês importa e o mês novo fica consultável" do
    batch = import_synthetic_workbook(volume_months: SHIFTED_MONTHS)

    assert_equal "validated", batch.reload.status
    september = ApplicationRecord.connection.select_value(
      "SELECT count(*) FROM monthly_volumes_consolidated WHERE period = DATE '2026-09-01'"
    )
    assert_operator september.to_i, :>, 0, "volumes de 202609 deveriam existir após o import"
    # As competências cobertas passam a vir do arquivo, não de lista fixa.
    assert_equal Date.new(2026, 9, 1), batch.covered_periods.map(&:to_date).max
  end

  test "famílias de volume com conjuntos de meses divergentes são recusadas" do
    headers = [
      *BinImport::Template::MAPA_BASE,
      "VOLUME DE FATURAMENTO TOTAL 202607", "VOLUME DE FATURAMENTO CRÉDITO 202607",
      "VOLUME DE FATURAMENTO DÉBITO 202607",
      # Antecipação traz outro mês: planilha malformada.
      "VOLUME DE ANTECIPAÇÃO 202608",
      "agenda_semanal"
    ]

    error = assert_raises(ArgumentError) { BinImport::Template.validate_mapa_headers!(headers) }
    assert_match(/mesmo conjunto de competências/, error.message)
  end

  test "divergência na parte fixa do Mapa continua fatal, como sempre foi" do
    headers = BinImport::Template::MAPA_FIXED_HEADERS - [ "NET MDR" ] +
      BinImport::Template::VOLUME_FAMILIES.map { |family| "#{family} 202607" }

    error = assert_raises(ArgumentError) { BinImport::Template.validate_mapa_headers!(headers) }
    assert_match(/Cabeçalhos divergentes/, error.message)
    assert_match(/NET MDR/, error.message)
  end

  test "mapa sem nenhuma coluna de volume é recusado" do
    error = assert_raises(ArgumentError) do
      BinImport::Template.validate_mapa_headers!(BinImport::Template::MAPA_FIXED_HEADERS.dup)
    end
    assert_match(/mesmo conjunto de competências/, error.message)
  end
end
