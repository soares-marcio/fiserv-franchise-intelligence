require "test_helper"

# A quarentena. O portal enxerga **um lote por Master** — o de maior id entre os validados —,
# então um arquivo parcial não acrescenta: ele vira a foto oficial, e o que não estiver nele
# some dos relatórios. Estes testes fixam que isso não acontece sem alguém olhar antes.
class BatchReviewTest < ActiveSupport::TestCase
  setup do
    @first_item = import_synthetic_workbook
    @channel = @first_item.channel
    refresh_audit_views
  end

  test "arquivo que remove EC para em revisão, e a carteira continua a de antes" do
    missing = BinWorkbook.default_stores.first(1)

    batch = import_as(nil, stores: missing, filename: "BIN_PARCIAL_20260812.xlsx")

    assert batch.pending_review?, "arquivo sem ECs conhecidos não pode consolidar direto"
    assert_includes batch.review_reasons, "removes_establishments"
    # Enquanto pendente, nenhuma tela o enxerga: o lote vigente continua sendo o primeiro.
    assert_equal @first_item.id, ImportBatch.validated.where(channel: @channel).maximum(:id)
  end

  test "o diff diz exatamente o que sairia, o que entra e o que muda de MIC" do
    batch = import_as(nil, stores: changed_stores, filename: "BIN_DIFF_20260812.xlsx")
    review = BatchReview.new(batch)

    # A planilha padrão tem três lojas e o arquivo novo traz uma delas: as outras duas saem.
    assert_equal %w[30000002 90000001], review.leaving.keys.sort, "os ECs ausentes são os que sairiam"
    assert_equal [ "30000099" ], review.entering.keys, "o EC novo é o que entra"
    assert_equal [ "30000001" ], review.moving.keys, "o EC que troca de MIC aparece à parte"
    assert_equal "MIC BETA", review.moving["30000001"][:to]
  end

  test "aprovar consolida e o lote passa a valer" do
    batch = import_as(nil, stores: changed_stores, filename: "BIN_APROVA_20260812.xlsx")
    revisor = User.create!(email_address: "revisa@exemplo.com", name: "Revisor",
      password: Accounts::PASSWORD, platform_admin: true)

    Operations::ReviewBatch.approve(batch: batch, reviewer: revisor, note: "Conferido com a Fiserv")

    assert batch.reload.validated?
    assert_equal revisor, batch.reviewed_by
    assert_equal batch.id, ImportBatch.validated.where(channel: @channel).maximum(:id)
    assert_operator DailyRevenueConsolidated.where(source_import_batch_id: batch.id).count, :>, 0,
      "aprovar é o que consolida"
  end

  test "recusar exige motivo e não consolida nada" do
    batch = import_as(nil, stores: changed_stores, filename: "BIN_RECUSA_20260812.xlsx")
    revisor = User.create!(email_address: "recusa@exemplo.com", name: "Revisor",
      password: Accounts::PASSWORD, platform_admin: true)

    assert_raises(ArgumentError) { Operations::ReviewBatch.reject(batch: batch, reviewer: revisor, note: " ") }

    Operations::ReviewBatch.reject(batch: batch, reviewer: revisor, note: "Arquivo veio pela metade")

    assert batch.reload.rejected?
    assert_equal "Arquivo veio pela metade", batch.review_note
    assert_equal 0, DailyRevenueConsolidated.where(source_import_batch_id: batch.id).count
    assert_equal @first_item.id, ImportBatch.validated.where(channel: @channel).maximum(:id)
  end

  test "quem não pode aprovar tem o envio retido mesmo sem remover nada" do
    guest = User.create!(organization: default_organization, email_address: "convidado@exemplo.com", name: "Convidado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    guest.access_grants.create!(channel: @channel)

    batch = import_as(guest, filename: "BIN_CONVIDADO_20260812.xlsx", stores: same_stores)

    assert batch.pending_review?
    assert_includes batch.review_reasons, "no_approval_permission"
  end

  test "quem pode aprovar e não remove nada consolida direto, como sempre foi" do
    operator = User.create!(organization: default_organization, email_address: "operador@exemplo.com", name: "Operador",
      password: Accounts::PASSWORD,
      permissions: [ Permission::BATCHES_UPLOAD, Permission::BATCHES_APPROVE ])
    operator.access_grants.create!(channel: @channel)

    batch = import_as(operator, filename: "BIN_OPERADOR_20260812.xlsx", stores: same_stores)

    assert batch.validated?, "sem motivo de revisão, o fluxo segue direto"
    assert_empty batch.review_reasons
  end

  # Dois falsos positivos que mandariam trabalho legítimo para a fila de revisão e fariam a
  # quarentena virar ruído — que é como uma guarda deixa de ser levada a sério.
  test "virada de competência não é queda de faturamento" do
    batch = import_as(nil, stores: same_stores, filename: "BIN_MES_20260905.xlsx")
    # A planilha sintética cobre sempre as mesmas competências; o que a regra precisa
    # enxergar é a diferença entre elas, e é isso que o ajuste abaixo monta.
    batch.update!(current_period: batch.current_period + 1.month)

    assert_nil BatchReview.new(batch).revenue_change,
      "meses diferentes não são comparáveis: o mês novo começa do zero"
  end

  test "arquivo que cobre menos dias da mesma competência não é queda de faturamento" do
    short_ones = BinWorkbook.default_stores.map do |store|
      store.class.new(**store.to_h.merge(current_days: store.current_days.select { |day, _| day <= 2 }))
    end

    batch = import_as(nil, stores: short_ones, filename: "BIN_CURTO_20260805.xlsx")

    assert_nil BatchReview.new(batch).revenue_change,
      "dentro do mês o valor é acumulado: menos dias é menos dinheiro por aritmética"
  end

  private

  # As mesmas lojas do primeiro arquivo, com um dia a mais de faturamento: o import recusa
  # dois arquivos idênticos, e o conteúdo precisa mudar.
  def same_stores
    BinWorkbook.default_stores.map do |store|
      store.class.new(**store.to_h.merge(current_days: store.current_days.merge(20 => 77)))
    end
  end

  # Um EC sai, um entra e um muda de MIC — os três casos que a tela de revisão mostra.
  def changed_stores
    base = BinWorkbook.default_stores
    first_row = base.first
    [
      first_row.class.new(**first_row.to_h.merge(sub_channel_name: "MIC BETA")),
      first_row.class.new(**first_row.to_h.merge(ec: "30000099", cnpj: "12345678000199",
        legal_name: "NOVA LOJA LTDA", trade_name: "NOVA"))
    ]
  end

  def import_as(author, stores: BinWorkbook.default_stores, filename: "BIN_TESTE_20260812.xlsx")
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    BinWorkbook.write(path, stores:)
    ImportBatch.create!(organization: default_organization, source_filename: filename, status: "pending", uploaded_by: author,
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: filename, organization: default_organization).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
