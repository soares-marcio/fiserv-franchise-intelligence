require "test_helper"

class BinImport::NormalizerTest < ActiveSupport::TestCase
  test "repõe zeros à esquerda perdidos pelo Excel nos identificadores de largura fixa" do
    assert_equal "01234567", BinImport::Normalizer.ec(1_234_567)
    assert_equal "01234567", BinImport::Normalizer.ec(1_234_567.0)
    assert_equal "00123456000199", BinImport::Normalizer.cnpj(123_456_000_199)
  end

  test "não completa zeros em texto: o que veio como string já tem o tamanho da origem" do
    assert_equal "12", BinImport::Normalizer.ec("12")
    assert_equal "123", BinImport::Normalizer.cnpj("123")
    assert_equal "1234567", BinImport::Normalizer.cep("1234-567")
  end

  test "preserva identificadores que já vêm completos" do
    assert_equal "92546997", BinImport::Normalizer.ec("92546997")
    assert_equal "55092685000135", BinImport::Normalizer.cnpj("55.092.685/0001-35")
  end

  test "não inventa dígitos quando o valor está vazio" do
    assert_equal "", BinImport::Normalizer.ec(nil)
    assert_equal "", BinImport::Normalizer.cnpj("")
    assert_equal "", BinImport::Normalizer.cep("  ")
  end

  test "não trunca valores maiores que a largura declarada" do
    assert_equal "123456789", BinImport::Normalizer.ec("123456789")
  end

  test "telefone continua sem largura fixa" do
    assert_equal "6230001111", BinImport::Normalizer.digits("(62) 3000-1111")
  end

  test "decimal aceita o formato pt-BR e o americano" do
    assert_equal BigDecimal("1234.56"), BinImport::Normalizer.decimal("1.234,56")
    assert_equal BigDecimal("1234.56"), BinImport::Normalizer.decimal("1234.56")
    assert_equal BigDecimal("1234.56"), BinImport::Normalizer.decimal(1234.56)
    assert_nil BinImport::Normalizer.decimal(nil)
    assert_nil BinImport::Normalizer.decimal("não é número")
  end

  test "date e boolean seguem a convenção da planilha" do
    assert_equal Date.new(2026, 2, 5), BinImport::Normalizer.date("2026-02-05")
    assert_nil BinImport::Normalizer.date("data inválida")
    assert BinImport::Normalizer.boolean("Sim")
    assert BinImport::Normalizer.boolean("ATIVO")
    assert_not BinImport::Normalizer.boolean("Não")
    assert_not BinImport::Normalizer.boolean(nil)
  end
end
