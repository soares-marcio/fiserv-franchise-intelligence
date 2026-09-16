require "test_helper"

# O selo do cabeçalho mostra dois sinais, e cada um tem um jeito de mentir. Estes testes fixam
# os dois: o geral é o pior de cada sinal, nunca o mais recente, e a data do arquivo sai no
# fuso do app.
class FileFreshnessTest < ActiveSupport::TestCase
  # O caso real de 16/09/2026: o arquivo mais novo da carteira era o do canal cujos dados
  # param em agosto. Somando o mais recente de cada coisa, o selo dizia "há 2 dias" em verde.
  test "o geral é o pior de cada sinal, e não o mais recente" do
    travel_to Time.zone.local(2026, 9, 16, 12) do
      canal_em_dia = canal("ALFA", recebido: 5.days.ago, cobertura: Date.new(2026, 9, 9))
      canal_atrasado = canal("BETA", recebido: 2.days.ago, cobertura: Date.new(2026, 8, 26))
      freshness = FileFreshness.new

      assert_equal [ "ALFA", "BETA" ], freshness.entries.map(&:name)
      assert_equal 5, freshness.received_days, "o upload mais antigo, e não o mais novo"
      assert_equal Date.new(2026, 8, 26), freshness.covered_on,
        "a cobertura mais antiga, que é a que não superestima o que a tela mostra"
      assert_not freshness.received_stale?, "nenhum canal passou de 12 dias sem arquivo"
      assert freshness.covered_stale?, "mas um deles tem dados de 21 dias atrás"

      por_nome = freshness.entries.index_by(&:name)

      assert_not por_nome["ALFA"].covered_stale?
      assert por_nome["BETA"].covered_stale?
      assert_equal [ canal_em_dia.id, canal_atrasado.id ].size, freshness.entries.size
    end
  end

  # O valor cru da consulta volta em UTC. Sem converter, um arquivo recebido às 21h de ontem
  # conta como de hoje, e o selo passa a dizer um dia a menos que a tela de importação.
  test "a data do arquivo sai no fuso do app" do
    travel_to Time.zone.local(2026, 9, 16, 12) do
      canal("ALFA", recebido: Time.zone.local(2026, 9, 14, 21, 15), cobertura: Date.new(2026, 9, 9))

      assert_equal Date.new(2026, 9, 14), FileFreshness.new.entries.first.received_on
      assert_equal 2, FileFreshness.new.received_days
      assert_equal ImportBatch.days_since_last_file, FileFreshness.new.received_days,
        "o selo e a tela de importação contam os mesmos dias"
    end
  end

  # Canal sem arquivo nenhum não é sinal verde: a ausência conta como atraso.
  test "canal sem arquivo conta como atrasado" do
    Channel.create!(name: "SEM ARQUIVO", external_id: "EXT-SEM-ARQUIVO")
    freshness = FileFreshness.new

    assert_nil freshness.entries.first.received_days
    assert freshness.received_stale?
    assert freshness.covered_stale?
    assert_not freshness.any_file?
  end

  private

  def canal(nome, recebido:, cobertura:)
    channel = Channel.create!(name: nome, external_id: "EXT-#{nome}")
    batch = ImportBatch.create!(channel:, status: "validated", source_filename: "#{nome}.xlsx",
      file_checksum: SecureRandom.hex(8), created_at: recebido)
    PeriodCoverage.create!(channel_id: channel.id, period: cobertura.beginning_of_month,
      max_known_day: cobertura.day, last_import_batch_id: batch.id)
    channel
  end
end
