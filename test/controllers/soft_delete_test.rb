require "test_helper"

# Apagar Master e MIC é marcar: os dados ficam, a carteira some de toda tela e só a
# plataforma restaura. O que estes testes garantem é que o apagado não aparece em lugar
# nenhum — nem pelo cache aquecido antes —, que o outro Master não muda, e que a planilha
# seguinte do mesmo REPORT_ID nasce como carteira nova.
class SoftDeleteTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  REPORT_SCREENS = %w[/reports /reports/stalled /reports/weekly /reports/three_months /reports/recurring
    /reports/indicators].freeze

  setup do
    import_synthetic_workbook
    @channel_a = Channel.find_by!(name: BinWorkbook::CHANNEL)
    @mic_beta = SubChannel.find_by!(name: "MIC BETA", channel: @channel_a)
    import_synthetic_workbook(stores: other_stores, filename: "BIN_OUTRO_20260812.xlsx",
      channel: "MASTER FRANQUEADO OUTRO", report_id: "8888")
    @channel_b = Channel.find_by!(name: "MASTER FRANQUEADO OUTRO")
    refresh_audit_views
    @admin = admin_user
  end

  test "o Master apagado some de toda tela, nem pelo cache, e o outro Master não muda" do
    with_real_cache do
      sign_in_as(@admin)
      before_b = establishments_of_b_on_screen
      REPORT_SCREENS.each { |screen| get(screen) }
      assert_match(/MIC ALFA/, response.body)

      post channel_deletion_path(@channel_a), params: { confirmation: BinWorkbook::CHANNEL }
      assert_redirected_to import_batches_path
      assert @channel_a.reload.deleted?
      # A mensagem de sucesso nomeia o Master; ela fica na tela do redirecionamento.
      follow_redirect!

      REPORT_SCREENS.each do |screen|
        get screen
        assert_response :success, screen
        assert_no_match(/MIC ALFA|MIC BETA|ALFA LANCHES|BETA CAFE/, response.body, "#{screen} mostra o Master apagado")
      end
      get establishments_path
      assert_no_match(/ALFA LANCHES|BETA CAFE/, response.body)
      get search_path(q: "ALFA")
      assert_no_match(/ALFA LANCHES|MIC ALFA/, response.body)
      get import_batches_path
      assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}/, response.body, "o painel de cobertura ainda lista o apagado")
      assert_equal before_b, establishments_of_b_on_screen
    end
  end

  test "apagar o Master guarda os dados, derruba as sessões de quem o tinha e registra na trilha" do
    collaborator = scoped_user(permissions: [ *Permission::REPORT_KEYS ], channel: @channel_a, email: "colab@exemplo.com")
    sign_in_as(collaborator)
    sign_out
    travel 31.seconds
    sign_in_as(collaborator)
    sign_out
    travel 31.seconds
    sign_in_as(@admin)
    rows_before = DailyRevenueConsolidated.where(channel: @channel_a).count

    post channel_deletion_path(@channel_a), params: { confirmation: BinWorkbook::CHANNEL }

    assert_equal rows_before, DailyRevenueConsolidated.where(channel: @channel_a).count, "apagar não remove dado"
    assert Establishment.where(channel: @channel_a).all? { |establishment| establishment.deleted_at.present? }
    assert ImportBatch.where(channel: @channel_a).all? { |batch| batch.deleted_at.present? }
    assert_equal 0, collaborator.sessions.count
    assert collaborator.access_grants.exists?(channel: @channel_a), "a concessão fica guardada para a restauração"
    assert AccessScope.for(collaborator).empty?, "mas não vale enquanto o Master estiver apagado"

    event = AuditEvent.find_by!(action: "channel.deleted")
    assert_equal BinWorkbook::CHANNEL, event.metadata["master"]
    assert_equal 3, event.metadata["ecs"]
    assert_no_match(/11222333000181|44555666000172/, event.metadata.to_json)
  end

  test "nome errado ou lote em revisão: nada é apagado" do
    sign_in_as(@admin)

    post channel_deletion_path(@channel_a), params: { confirmation: "outro nome" }
    assert_response :unprocessable_entity
    assert_not @channel_a.reload.deleted?

    ImportBatch.create!(source_filename: "revisar.xlsx", file_checksum: "rev-1", status: "pending_review",
      channel: @channel_a, uploaded_by: @admin)
    post channel_deletion_path(@channel_a), params: { confirmation: BinWorkbook::CHANNEL }
    assert_response :unprocessable_entity
    assert_match(/em revisão/, response.body)
    assert_not @channel_a.reload.deleted?
  end

  test "só o administrador da organização dona apaga; a plataforma e o colaborador não" do
    sign_in_as(scoped_user(permissions: [ *Permission::REPORT_KEYS, Permission::BATCHES_UPLOAD ],
      channel: @channel_a, email: "colab@exemplo.com"))
    get new_channel_deletion_path(@channel_a)
    assert_response :forbidden
    sign_out

    travel 31.seconds
    sign_in_as(platform_admin_user)
    post channel_deletion_path(@channel_a), params: { confirmation: BinWorkbook::CHANNEL }
    assert_response :forbidden
    sign_out

    travel 31.seconds
    other = Organization.create!(name: "Outra")
    sign_in_as(admin_user(email: "outra@exemplo.com", organization: other))
    get new_channel_deletion_path(@channel_a)
    assert_response :not_found
    assert_not @channel_a.reload.deleted?
  end

  test "a planilha do REPORT_ID apagado cria um Master novo, e o apagado continua apagado" do
    Operations::SoftDelete.delete_channel(channel: @channel_a, actor: @admin, confirmation: BinWorkbook::CHANNEL)

    import_synthetic_workbook(filename: "BIN_TESTE_20260820.xlsx")

    fresh = Channel.active.find_by!(external_id: BinWorkbook::REPORT_ID)
    assert_not_equal @channel_a.id, fresh.id
    assert @channel_a.reload.deleted?
    assert_equal 2, Establishment.where(ec: "30000001").count, "o mesmo EC existe no apagado e no novo"
    assert_equal fresh.id, Establishment.active.find_by!(ec: "30000001").channel_id

    Operations::SoftDelete.delete_channel(channel: fresh, actor: @admin, confirmation: BinWorkbook::CHANNEL)
    sign_in_as(platform_admin_user)
    get platform_organization_path(default_organization)
    assert_equal 2, response.body.scan("Master · REPORT_ID #{BinWorkbook::REPORT_ID}").size,
      "a plataforma lista os dois apagados"
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}/, response.body, "a plataforma não lê o nome da carteira")
  end

  test "a plataforma restaura tudo, e recusa quando uma planilha nova já ocupou o REPORT_ID" do
    collaborator = scoped_user(permissions: [ *Permission::REPORT_KEYS ], channel: @channel_a, email: "colab@exemplo.com")
    Operations::SoftDelete.delete_channel(channel: @channel_a, actor: @admin, confirmation: BinWorkbook::CHANNEL)
    sign_in_as(platform_admin_user)

    post restore_platform_channel_path(@channel_a)

    assert_not @channel_a.reload.deleted?
    assert Establishment.where(channel: @channel_a).all? { |establishment| establishment.deleted_at.nil? }
    assert ImportBatch.where(channel: @channel_a).all? { |batch| batch.deleted_at.nil? }
    assert_equal [ @channel_a.id ], AccessScope.for(collaborator).channel_ids, "o acesso volta com o Master"
    assert AuditEvent.exists?(action: "channel.restored")

    Operations::SoftDelete.delete_channel(channel: @channel_a, actor: @admin, confirmation: BinWorkbook::CHANNEL)
    import_synthetic_workbook(filename: "BIN_TESTE_20260821.xlsx")
    post restore_platform_channel_path(@channel_a)
    assert_match(/já tem um Master ativo/, flash[:alert])
    assert @channel_a.reload.deleted?
  end

  test "o administrador da organização não restaura" do
    Operations::SoftDelete.delete_channel(channel: @channel_a, actor: @admin, confirmation: BinWorkbook::CHANNEL)
    sign_in_as(@admin)

    post restore_platform_channel_path(@channel_a)

    assert_response :forbidden
    assert @channel_a.reload.deleted?
  end

  test "o MIC apagado some das telas e dos totais; o Master continua inteiro para importar" do
    with_real_cache do
      sign_in_as(@admin)
      REPORT_SCREENS.each { |screen| get(screen) }
      get reports_path(channel_id: @channel_a.uuid)
      total_before = response.body[/Mês anterior cheio<\/p>\s*<p class="metric-value">([^<]+)/, 1]

      post sub_channel_deletion_path(@mic_beta), params: { confirmation: "MIC BETA" }
      assert_redirected_to reports_path
      assert @mic_beta.reload.deleted?
      follow_redirect!

      REPORT_SCREENS.each do |screen|
        get screen
        assert_no_match(/MIC BETA|BETA CAFE/, response.body, "#{screen} mostra o MIC apagado")
      end
      assert_match(/MIC ALFA/, response.body)
      get reports_path(channel_id: @channel_a.uuid)
      assert_not_equal total_before, response.body[/Mês anterior cheio<\/p>\s*<p class="metric-value">([^<]+)/, 1],
        "o total do Master ainda soma o MIC apagado"
      get sub_channel_report_path(@mic_beta)
      assert_response :not_found
      get establishments_path
      assert_no_match(/BETA CAFE/, response.body)

      scope = AccessScope.for(@admin)
      assert scope.whole?(@channel_a.id), "o administrador continua dono do Master inteiro"
      assert scope.partial?
    end
  end

  test "o MIC volta como MIC novo na planilha seguinte; a restauração recusa o nome repetido" do
    Operations::SoftDelete.delete_sub_channel(sub_channel: @mic_beta, actor: @admin, confirmation: "MIC BETA")

    import_synthetic_workbook(filename: "BIN_TESTE_20260822.xlsx", stores: stores_with_one_more_day)

    fresh = SubChannel.active.find_by!(channel: @channel_a, name: "MIC BETA")
    assert_not_equal @mic_beta.id, fresh.id
    sign_in_as(@admin)
    get establishments_path
    assert_match(/BETA CAFE/, response.body, "o EC volta pelo MIC novo")

    assert_raises(ArgumentError) { Operations::SoftDelete.restore_sub_channel(sub_channel: @mic_beta) }
  end

  test "colaborador com o MIC apagado perde o acesso a ele; com o Master inteiro, deixa de vê-lo" do
    by_mic = scoped_user(permissions: [ *Permission::REPORT_KEYS ], sub_channel: @mic_beta, email: "mic@exemplo.com")
    whole = scoped_user(permissions: [ *Permission::REPORT_KEYS ], channel: @channel_a, email: "master@exemplo.com")

    Operations::SoftDelete.delete_sub_channel(sub_channel: @mic_beta, actor: @admin, confirmation: "MIC BETA")

    assert AccessScope.for(by_mic).empty?
    sign_in_as(whole)
    get reports_path
    assert_no_match(/MIC BETA/, response.body)
    assert_match(/MIC ALFA/, response.body)
  end

  private

  def establishments_of_b_on_screen
    get establishments_path
    response.body.scan(/OMEGA[^<]*/).sort
  end

  def stores_with_one_more_day
    BinWorkbook.default_stores.map do |store|
      store.class.new(**store.to_h.merge(current_days: store.current_days.merge(20 => 77)))
    end
  end

  def other_stores
    [
      BinWorkbook::Store.new(
        ec: "70000001", cnpj: "99888777000166", sub_channel_name: "MIC OMEGA",
        legal_name: "OMEGA COMERCIO LTDA", trade_name: "OMEGA",
        contract_status: "Active", previous_days: { 1 => 500 }, current_days: { 1 => 900 }
      )
    ]
  end

  def with_real_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
