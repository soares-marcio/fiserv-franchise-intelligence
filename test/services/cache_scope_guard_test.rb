require "test_helper"

# Toda chave de cache carrega o escopo. Uma chave sem ele serve o resultado de um recorte
# a outro, sem erro nenhum: foi assim que a tela Ganhos 3M mostrou a quem tinha um MIC os
# MICs de quem carregara a tela antes (30/09/2026). Este guarda lê o código: quem escrever
# um Rails.cache.fetch sem `cache_key` por perto quebra aqui, não em produção.
class CacheScopeGuardTest < ActiveSupport::TestCase
  test "todo Rails.cache.fetch do app leva o cache_key do escopo na chave" do
    without_scope = Dir[Rails.root.join("app/**/*.rb")].flat_map do |file|
      rows = File.readlines(file)
      rows.each_index.filter_map do |i|
        next unless rows[i].include?("Rails.cache.fetch")
        # A chave pode ser montada nas linhas logo acima (`key = [...]`).
        excerpt = rows[[ i - 3, 0 ].max..i].join
        "#{file.delete_prefix(Rails.root.to_s + '/')}:#{i + 1}" unless excerpt.include?("cache_key")
      end
    end

    assert_empty without_scope, "chave de cache sem o escopo em: #{without_scope.join(', ')}"
  end

  test "o guarda encontra os usos de cache que existem" do
    usages = Dir[Rails.root.join("app/**/*.rb")].sum { |file| File.read(file).scan("Rails.cache.fetch").size }

    assert_operator usages, :>=, 4, "o guarda não está lendo os serviços"
  end
end
