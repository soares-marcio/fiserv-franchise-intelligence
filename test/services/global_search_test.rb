require "test_helper"

# Busca do header: dois caracteres já valem, e um resultado vazio precisa distinguir
# "não achei" de "ainda não há dado importado".
class GlobalSearchTest < ActiveSupport::TestCase
  test "sem lote validado a base está vazia e nada é procurado" do
    search = GlobalSearch.new("alfa")

    assert_predicate search, :base_empty?
    assert_empty search.establishments
  end

  test "termo curto demais não vira consulta" do
    import_synthetic_workbook
    search = GlobalSearch.new("a")

    assert_not search.searchable?
    assert_empty search.sub_channels
    assert_empty search.establishments
    assert_not search.empty?, "termo curto não é 'nada encontrado', é busca não feita"
  end

  test "acha o subcanal pelo nome, em qualquer caixa" do
    import_synthetic_workbook

    assert_equal [ "MIC ALFA" ], GlobalSearch.new("mic alfa").sub_channels.map(&:name)
  end

  test "acha o estabelecimento por EC, nome fantasia e CNPJ colado com máscara" do
    import_synthetic_workbook

    assert_equal [ "30000002" ], GlobalSearch.new("30000002").establishments.map(&:ec)
    assert_equal [ "30000002" ], GlobalSearch.new("beta cafe").establishments.map(&:ec)
    assert_equal [ "30000002" ], GlobalSearch.new("44.555.666/0001-72").establishments.map(&:ec)
  end

  test "termo sem correspondência é busca vazia, com base preenchida" do
    import_synthetic_workbook
    search = GlobalSearch.new("zzzz")

    assert_not search.base_empty?
    assert_predicate search, :empty?
  end

  test "espaços em volta do termo não contam como conteúdo" do
    import_synthetic_workbook

    assert_not GlobalSearch.new("  a  ").searchable?
    assert_equal [ "30000002" ], GlobalSearch.new("  beta cafe  ").establishments.map(&:ec)
  end
end

class SearchNormalizerTest < ActiveSupport::TestCase
  test "CNPJ e EC colados com pontuação viram só dígitos" do
    assert_equal "44555666000172", SearchNormalizer.digits("44.555.666/0001-72")
    assert_equal "30000002", SearchNormalizer.digits(" 3000 0002 ")
  end

  test "poucos dígitos viram nada: casariam com quase tudo" do
    assert_nil SearchNormalizer.digits("12")
    assert_nil SearchNormalizer.digits("beta")
    assert_nil SearchNormalizer.digits(nil)
  end

  test "o mínimo de dígitos é ajustável por chamada" do
    assert_equal "12", SearchNormalizer.digits("12", min_length: 2)
  end
end
