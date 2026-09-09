require "test_helper"

# A oferta pré-aprovada é do CNPJ, não do EC: na carteira real, os 15 CNPJs com oferta no
# lote mais recente somam 30 ECs e produzem 15 combinações distintas de CNPJ e volume — ou
# seja, todos os ECs de um CNPJ trazem a mesma oferta. A listagem existe por causa disso.
class PreapprovedOffersTest < ActiveSupport::TestCase
  setup do
    import_synthetic_workbook(lojas: lojas)
  end

  test "uma linha por CNPJ, com os quatro campos da planilha" do
    linhas = PreapprovedOffers.new.call

    assert_equal 1, linhas.size, "dois ECs do mesmo CNPJ são um cliente"
    linha = linhas.first
    assert_equal "11222333000181", linha["cnpj"]
    assert_equal "ALFA COMERCIO LTDA", linha["legal_name"]
    assert_equal 350_000.to_d, linha["preapproved_volume"].to_d
    assert_equal 24, linha["preapproved_term"].to_i
    assert_equal 3.28.to_d, linha["preapproved_rate"].to_d
  end

  test "CNPJ sem oferta na planilha fica de fora" do
    assert_empty PreapprovedOffers.new.call.select { |row| row["cnpj"] == "22333444000105" }
  end

  # A invariante que o usuário declarou e que a carteira confirma. Se uma planilha futura
  # trouxer ofertas diferentes entre ECs do mesmo CNPJ, a tela passa a escolher uma em
  # silêncio — e é este teste que precisa gritar antes disso acontecer na tela.
  test "acusa quando os ECs do mesmo CNPJ divergem na oferta" do
    MapSnapshot.joins(:establishment).where(establishments: { ec: "30000002" })
      .update_all(preapproved_volume: 999)

    assert_equal 1, PreapprovedOffers.new.call.size,
      "a listagem continua com uma linha por CNPJ"
    assert PreapprovedOffers.new.diverging_cnpjs.any?,
      "e a divergência precisa ser detectável, não silenciosa"
  end

  # Achado na carteira real: 3 dos 366 CNPJs têm ECs que discordam da própria razão social,
  # e 2 deles estão entre os 15 com oferta. O caso visto é um EC trazendo o nome fantasia na
  # coluna da razão — e como "START KLIN" vem depois de "MARCA HIGIENE…" no alfabeto, um
  # MAX() elegia o fantasia. A escolha é do nome que a maioria dos ECs declara.
  test "com razão social divergente entre ECs, fica com a que a maioria declara" do
    MapSnapshot.joins(:establishment).where(establishments: { ec: "30000002" })
      .update_all(legal_name: "ZZZ NOME FANTASIA")

    linha = PreapprovedOffers.new.call.first

    assert_equal "ALFA COMERCIO LTDA", linha["legal_name"],
      "dois ECs dizem a razão social e um discorda: vence a maioria, não o alfabeto"
    assert_includes PreapprovedOffers.new.diverging_name_cnpjs, "11222333000181",
      "e a divergência aparece, em vez de a tela escolher em silêncio"
  end

  # Mesmo cuidado do listing: o LEFT JOIN da anotação entra numa consulta com GROUP BY, e
  # aqui a garantia que importa é continuar uma linha por CNPJ.
  test "a anotação chega sem quebrar a linha por CNPJ" do
    Operations::SaveCompanyNote.call(cnpj: "11222333000181", body: "<div>Ligar.</div>")

    linhas = PreapprovedOffers.new.call

    assert_equal 1, linhas.size
    assert_predicate linhas.first["company_uuid"], :present?
    assert_predicate linhas.first["note_id"], :present?
  end

  # A coluna PARCELA_PRE_APROVADA existe no arquivo da Fiserv e nunca trouxe valor: zero em
  # 2.220 snapshots. A consulta a expõe assim mesmo — quem lê a tela precisa ver a lacuna,
  # não um número inventado a partir de volume, prazo e taxa.
  test "a parcela vem como veio da planilha, sem cálculo" do
    assert_nil PreapprovedOffers.new.call.first["preapproved_installment"]
  end

  private

  def lojas
    [
      # Dois ECs do mesmo CNPJ, com a mesma oferta: é o caso real.
      BinWorkbook::Loja.new(
        ec: "30000001", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO LTDA", trade_name: "ALFA LANCHES",
        contract_status: "Active", dias_m1: { 1 => 100 }, dias_atual: { 1 => 150 },
        preapproved_volume: 350_000, preapproved_term: 24, preapproved_rate: 3.28
      ),
      BinWorkbook::Loja.new(
        ec: "30000002", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO LTDA", trade_name: "ALFA EXPRESS",
        contract_status: "Active", dias_m1: { 1 => 50 }, dias_atual: { 1 => 20 },
        preapproved_volume: 350_000, preapproved_term: 24, preapproved_rate: 3.28
      ),
      # Um terceiro EC no mesmo CNPJ: com dois contra um, "a maioria declara" é uma maioria
      # de verdade, não um desempate alfabético disfarçado.
      BinWorkbook::Loja.new(
        ec: "30000004", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
        legal_name: "ALFA COMERCIO LTDA", trade_name: "ALFA DELIVERY",
        contract_status: "Active", dias_m1: { 1 => 30 }, dias_atual: { 1 => 40 },
        preapproved_volume: 350_000, preapproved_term: 24, preapproved_rate: 3.28
      ),
      # Sem oferta: a maioria da carteira (531 dos 561 ECs do lote real).
      BinWorkbook::Loja.new(
        ec: "30000003", cnpj: "22333444000105", sub_channel_name: "MIC ALFA",
        legal_name: "BETA SERVICOS LTDA", trade_name: "BETA CAFE",
        contract_status: "Active", dias_m1: { 1 => 400 }, dias_atual: { 1 => 300 }
      )
    ]
  end
end
