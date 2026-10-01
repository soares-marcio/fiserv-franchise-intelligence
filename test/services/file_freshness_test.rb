require "test_helper"

# O selo do cabeçalho mostra dois sinais, e cada um tem um jeito de mentir. Estes testes fixam
# os dois: o geral é o pior de cada sinal, nunca o mais recente, e a data do arquivo sai no
# fuso do app.
class FileFreshnessTest < ActiveSupport::TestCase
  # O caso real de 16/09/2026: o arquivo mais novo da carteira era o do canal cujos dados
  # param em agosto. Somando o mais recente de cada coisa, o selo dizia "há 2 dias" em verde.
  test "o geral é o pior de cada sinal, e não o mais recente" do
    travel_to Time.zone.local(2026, 9, 16, 12) do
      fresh_channel = channel("ALFA", received: 5.days.ago, coverage: Date.new(2026, 9, 9))
      stale_channel = channel("BETA", received: 2.days.ago, coverage: Date.new(2026, 8, 26))
      freshness = FileFreshness.new(organization: default_organization)

      assert_equal [ "ALFA", "BETA" ], freshness.entries.map(&:name)
      assert_equal 5, freshness.received_days, "o upload mais antigo, e não o mais novo"
      assert_equal Date.new(2026, 8, 26), freshness.covered_on,
        "a cobertura mais antiga, que é a que não superestima o que a tela mostra"
      assert_not freshness.received_stale?, "nenhum canal passou de 12 dias sem arquivo"
      assert freshness.covered_stale?, "mas um deles tem dados de 21 dias atrás"

      by_name = freshness.entries.index_by(&:name)

      assert_not by_name["ALFA"].covered_stale?
      assert by_name["BETA"].covered_stale?
      assert_equal [ fresh_channel.id, stale_channel.id ].size, freshness.entries.size
    end
  end

  # O valor cru da consulta volta em UTC. Sem converter, um arquivo recebido às 21h de ontem
  # conta como de hoje, e o selo passa a dizer um dia a menos que a tela de importação.
  test "a data do arquivo sai no fuso do app" do
    travel_to Time.zone.local(2026, 9, 16, 12) do
      channel("ALFA", received: Time.zone.local(2026, 9, 14, 21, 15), coverage: Date.new(2026, 9, 9))

      assert_equal Date.new(2026, 9, 14), FileFreshness.new(organization: default_organization).entries.first.received_on
      assert_equal 2, FileFreshness.new(organization: default_organization).received_days
      assert_equal ImportBatch.days_since_last_file(organization: default_organization), FileFreshness.new(organization: default_organization).received_days,
        "o selo e a tela de importação contam os mesmos dias"
    end
  end

  # Canal sem arquivo nenhum não é sinal verde: a ausência conta como atraso.
  test "canal sem arquivo conta como atrasado" do
    Channel.create!(organization: default_organization, name: "SEM ARQUIVO", external_id: "EXT-SEM-ARQUIVO")
    freshness = FileFreshness.new(organization: default_organization)

    assert_nil freshness.entries.first.received_days
    assert freshness.received_stale?
    assert freshness.covered_stale?
    assert_not freshness.any_file?
  end

  # A carteira de outra organização não entra no selo de ninguém — nem como atraso.
  test "canal de outra organização fica fora do selo" do
    other = Organization.create!(name: "Outra")
    Channel.create!(organization: other, name: "DE OUTRA", external_id: "EXT-OUTRA")
    channel("ALFA", received: 1.day.ago, coverage: Date.current)

    freshness = FileFreshness.new(organization: default_organization)

    assert_equal [ "ALFA" ], freshness.entries.map(&:name)
    assert_not freshness.received_stale?
    assert_empty FileFreshness.new(organization: nil).entries, "a plataforma não tem carteira a medir"
  end

  private

  def channel(name, received:, coverage:)
    channel = Channel.create!(organization: default_organization, name: name, external_id: "EXT-#{name}")
    batch = ImportBatch.create!(channel:, status: "validated", source_filename: "#{name}.xlsx",
      file_checksum: SecureRandom.hex(8), created_at: received)
    PeriodCoverage.create!(channel_id: channel.id, period: coverage.beginning_of_month,
      max_known_day: coverage.day, last_import_batch_id: batch.id)
    channel
  end
end
