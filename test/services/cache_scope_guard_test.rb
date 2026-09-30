require "test_helper"

# Toda chave de cache carrega o escopo. Uma chave sem ele serve o resultado de um recorte
# a outro, sem erro nenhum: foi assim que a tela Ganhos 3M mostrou a quem tinha um MIC os
# MICs de quem carregara a tela antes (30/09/2026). Este guarda lê o código: quem escrever
# um Rails.cache.fetch sem `cache_key` por perto quebra aqui, não em produção.
class CacheScopeGuardTest < ActiveSupport::TestCase
  test "todo Rails.cache.fetch do app leva o cache_key do escopo na chave" do
    sem_escopo = Dir[Rails.root.join("app/**/*.rb")].flat_map do |arquivo|
      linhas = File.readlines(arquivo)
      linhas.each_index.filter_map do |i|
        next unless linhas[i].include?("Rails.cache.fetch")
        # A chave pode ser montada nas linhas logo acima (`key = [...]`).
        trecho = linhas[[ i - 3, 0 ].max..i].join
        "#{arquivo.delete_prefix(Rails.root.to_s + '/')}:#{i + 1}" unless trecho.include?("cache_key")
      end
    end

    assert_empty sem_escopo, "chave de cache sem o escopo em: #{sem_escopo.join(', ')}"
  end

  test "o guarda encontra os usos de cache que existem" do
    usos = Dir[Rails.root.join("app/**/*.rb")].sum { |arquivo| File.read(arquivo).scan("Rails.cache.fetch").size }

    assert_operator usos, :>=, 4, "o guarda não está lendo os serviços"
  end
end
