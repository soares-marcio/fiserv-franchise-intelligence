require "test_helper"

# A guarda de identidade roda antes de gravar qualquer linha: um EC que troca de CNPJ ou de
# canal entre planilhas significa arquivo errado, não cadastro novo.
class BinImport::IdentityGuardTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

  setup do
    import_synthetic_workbook
    @channel = Channel.first
    @alfa = Establishment.find_by(ec: "30000001")
  end

  test "aceita planilha em que os ECs conhecidos mantêm CNPJ e canal" do
    assert_nothing_raised do
      BinImport::IdentityGuard.assert_existing!(@channel, sheets(row(@alfa.ec, "11.222.333/0001-81")))
    end
  end

  test "recusa EC que muda de CNPJ entre importações" do
    error = assert_raises(ArgumentError) do
      BinImport::IdentityGuard.assert_existing!(@channel, sheets(row(@alfa.ec, "99.888.777/0001-66")))
    end

    assert_match(/EC 30000001 já está cadastrado com outro CNPJ/, error.message)
  end

  test "recusa EC que muda de canal entre importações" do
    other = Channel.create!(external_id: "999", name: "OUTRO CANAL")

    error = assert_raises(ArgumentError) do
      BinImport::IdentityGuard.assert_existing!(other, sheets(row(@alfa.ec, "11.222.333/0001-81")))
    end

    assert_match(/EC 30000001 já pertence a outro canal/, error.message)
  end

  test "EC desconhecido passa: é cadastro novo, não divergência" do
    assert_nothing_raised do
      BinImport::IdentityGuard.assert_existing!(@channel, sheets(row("39999999", "99.888.777/0001-66")))
    end
  end

  # Um SELECT por linha de cada aba fazia o custo crescer com o tamanho da planilha, dentro
  # do caminho crítico do import: as três abas repetem os mesmos ECs.
  test "consulta os ECs de uma vez, não uma vez por linha" do
    rows = sheets(*Establishment.pluck(:ec).map { |ec| row(ec, Establishment.find_by(ec:).company.cnpj) })

    # uncached: o query cache da requisição esconderia a repetição entre as abas, mas não
    # o custo de um EC distinto por vez, que é o que cresce com a planilha.
    assert_queries_count(2) do
      ApplicationRecord.uncached { BinImport::IdentityGuard.assert_existing!(@channel, rows) }
    end
  end

  private

  def row(ec, cnpj) = { "EC" => ec, "CNPJ" => cnpj }

  # As três abas trazem as mesmas lojas; a guarda percorre todas.
  def sheets(*rows)
    BinImport::Template::SHEETS.to_h { |sheet| [ sheet, rows ] }
  end
end
