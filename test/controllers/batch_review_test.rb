require "test_helper"

# A quarentena. O portal enxerga **um lote por Master** — o de maior id entre os validados —,
# então um arquivo parcial não acrescenta: ele vira a foto oficial, e o que não estiver nele
# some dos relatórios. Estes testes fixam que isso não acontece sem alguém olhar antes.
class BatchReviewTest < ActiveSupport::TestCase
  setup do
    @primeiro = import_synthetic_workbook
    @canal = @primeiro.channel
    refresh_audit_views
  end

  test "arquivo que remove EC para em revisão, e a carteira continua a de antes" do
    faltando = BinWorkbook.default_lojas.first(1)

    lote = import_como(nil, lojas: faltando, filename: "BIN_PARCIAL_20260812.xlsx")

    assert lote.pending_review?, "arquivo sem ECs conhecidos não pode consolidar direto"
    assert_includes lote.review_reasons, "removes_establishments"
    # Enquanto pendente, nenhuma tela o enxerga: o lote vigente continua sendo o primeiro.
    assert_equal @primeiro.id, ImportBatch.validated.where(channel: @canal).maximum(:id)
  end

  test "o diff diz exatamente o que sairia, o que entra e o que muda de MIC" do
    lote = import_como(nil, lojas: lojas_alteradas, filename: "BIN_DIFF_20260812.xlsx")
    review = BatchReview.new(lote)

    # A planilha padrão tem três lojas e o arquivo novo traz uma delas: as outras duas saem.
    assert_equal %w[30000002 90000001], review.leaving.keys.sort, "os ECs ausentes são os que sairiam"
    assert_equal [ "30000099" ], review.entering.keys, "o EC novo é o que entra"
    assert_equal [ "30000001" ], review.moving.keys, "o EC que troca de MIC aparece à parte"
    assert_equal "MIC BETA", review.moving["30000001"][:to]
  end

  test "aprovar consolida e o lote passa a valer" do
    lote = import_como(nil, lojas: lojas_alteradas, filename: "BIN_APROVA_20260812.xlsx")
    revisor = User.create!(email_address: "revisa@exemplo.com", name: "Revisor",
      password: Accounts::PASSWORD, super_admin: true)

    Operations::ReviewBatch.approve(batch: lote, reviewer: revisor, note: "Conferido com a Fiserv")

    assert lote.reload.validated?
    assert_equal revisor, lote.reviewed_by
    assert_equal lote.id, ImportBatch.validated.where(channel: @canal).maximum(:id)
    assert_operator DailyRevenueConsolidated.where(source_import_batch_id: lote.id).count, :>, 0,
      "aprovar é o que consolida"
  end

  test "recusar exige motivo e não consolida nada" do
    lote = import_como(nil, lojas: lojas_alteradas, filename: "BIN_RECUSA_20260812.xlsx")
    revisor = User.create!(email_address: "recusa@exemplo.com", name: "Revisor",
      password: Accounts::PASSWORD, super_admin: true)

    assert_raises(ArgumentError) { Operations::ReviewBatch.reject(batch: lote, reviewer: revisor, note: " ") }

    Operations::ReviewBatch.reject(batch: lote, reviewer: revisor, note: "Arquivo veio pela metade")

    assert lote.reload.rejected?
    assert_equal "Arquivo veio pela metade", lote.review_note
    assert_equal 0, DailyRevenueConsolidated.where(source_import_batch_id: lote.id).count
    assert_equal @primeiro.id, ImportBatch.validated.where(channel: @canal).maximum(:id)
  end

  test "quem não pode aprovar tem o envio retido mesmo sem remover nada" do
    convidado = User.create!(email_address: "convidado@exemplo.com", name: "Convidado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    convidado.access_grants.create!(channel: @canal)

    lote = import_como(convidado, filename: "BIN_CONVIDADO_20260812.xlsx", lojas: mesmas_lojas)

    assert lote.pending_review?
    assert_includes lote.review_reasons, "no_approval_permission"
  end

  test "quem pode aprovar e não remove nada consolida direto, como sempre foi" do
    operador = User.create!(email_address: "operador@exemplo.com", name: "Operador",
      password: Accounts::PASSWORD,
      permissions: [ Permission::BATCHES_UPLOAD, Permission::BATCHES_APPROVE ])
    operador.access_grants.create!(channel: @canal)

    lote = import_como(operador, filename: "BIN_OPERADOR_20260812.xlsx", lojas: mesmas_lojas)

    assert lote.validated?, "sem motivo de revisão, o fluxo segue direto"
    assert_empty lote.review_reasons
  end

  # Dois falsos positivos que mandariam trabalho legítimo para a fila de revisão e fariam a
  # quarentena virar ruído — que é como uma guarda deixa de ser levada a sério.
  test "virada de competência não é queda de faturamento" do
    lote = import_como(nil, lojas: mesmas_lojas, filename: "BIN_MES_20260905.xlsx")
    # A planilha sintética cobre sempre as mesmas competências; o que a regra precisa
    # enxergar é a diferença entre elas, e é isso que o ajuste abaixo monta.
    lote.update!(current_period: lote.current_period + 1.month)

    assert_nil BatchReview.new(lote).revenue_change,
      "meses diferentes não são comparáveis: o mês novo começa do zero"
  end

  test "arquivo que cobre menos dias da mesma competência não é queda de faturamento" do
    curtas = BinWorkbook.default_lojas.map do |loja|
      loja.class.new(**loja.to_h.merge(dias_atual: loja.dias_atual.select { |dia, _| dia <= 2 }))
    end

    lote = import_como(nil, lojas: curtas, filename: "BIN_CURTO_20260805.xlsx")

    assert_nil BatchReview.new(lote).revenue_change,
      "dentro do mês o valor é acumulado: menos dias é menos dinheiro por aritmética"
  end

  private

  # As mesmas lojas do primeiro arquivo, com um dia a mais de faturamento: o import recusa
  # dois arquivos idênticos, e o conteúdo precisa mudar.
  def mesmas_lojas
    BinWorkbook.default_lojas.map do |loja|
      loja.class.new(**loja.to_h.merge(dias_atual: loja.dias_atual.merge(20 => 77)))
    end
  end

  # Um EC sai, um entra e um muda de MIC — os três casos que a tela de revisão mostra.
  def lojas_alteradas
    base = BinWorkbook.default_lojas
    primeira = base.first
    [
      primeira.class.new(**primeira.to_h.merge(sub_channel_name: "MIC BETA")),
      primeira.class.new(**primeira.to_h.merge(ec: "30000099", cnpj: "12345678000199",
        legal_name: "NOVA LOJA LTDA", trade_name: "NOVA"))
    ]
  end

  def import_como(autor, lojas: BinWorkbook.default_lojas, filename: "BIN_TESTE_20260812.xlsx")
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    BinWorkbook.write(path, lojas:)
    ImportBatch.create!(source_filename: filename, status: "pending", uploaded_by: autor,
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: filename).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
