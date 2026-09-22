require "test_helper"

# Uma permissão por vez: o ator entra com a chave em questão e sem ela, e a tela responde
# diferente. É o que impede uma policy virar enfeite — negar por padrão só vale se alguém
# provar que a negativa acontece.
class AuthorizationTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @batch = ImportBatch.create!(source_filename: "planilha.xlsx", file_checksum: "lote-1", status: "failed")
  end

  test "sem permissão de ver relatório, a tela responde 403" do
    entra_com([])

    get reports_path

    assert_response :forbidden
  end

  test "com permissão de ver relatório, a tela abre" do
    entra_com([ Permission::REPORTS_READ ])

    get reports_path

    assert_response :success
  end

  # Exportar leva a carteira inteira num arquivo, sem paginação: é decisão separada de ver
  # a tela, e o teste cobre as duas pontas.
  test "ver relatório não dá direito de exportar" do
    entra_com([ Permission::REPORTS_READ ])

    get recurring_reports_path(format: :csv)

    assert_response :forbidden
  end

  test "com a chave de exportação, o arquivo sai" do
    entra_com([ Permission::REPORTS_READ, Permission::REPORTS_EXPORT ])

    get recurring_reports_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
  end

  test "estabelecimentos e busca dependem da mesma chave" do
    entra_com([ Permission::REPORTS_READ ])

    get establishments_path
    assert_response :forbidden

    get search_path(q: "alfa")
    assert_response :forbidden

    entra_com([ Permission::ESTABLISHMENTS_READ ], email: "outro@exemplo.com")

    get establishments_path
    assert_response :success

    get search_path(q: "alfa")
    assert_response :success
  end

  test "a tela do Metabase exige a própria chave, porque mostra dados de conexão" do
    entra_com([ Permission::REPORTS_READ ])

    get metabase_path

    assert_response :forbidden
  end

  # O lote é do próprio ator: assim o que se mede aqui é a falta da chave, e não a falta de
  # alcance — lote de terceiro responde 404, e isso é assunto do teste de acesso a lotes.
  test "ver lotes não dá direito de enviar, ajustar nem descartar" do
    ator = entra_com([ Permission::BATCHES_READ ])
    @batch.update!(uploaded_by: ator)

    get import_batches_path
    assert_response :success

    post import_batches_path, params: { file: nil }
    assert_response :forbidden

    post reprocess_import_batch_path(@batch)
    assert_response :forbidden

    patch update_cutoff_import_batch_path(@batch), params: { max_known_day: 10 }
    assert_response :forbidden

    assert_no_difference -> { ImportBatch.count } do
      delete import_batch_path(@batch)
    end
    assert_response :forbidden
  end

  test "descartar exige a chave de descarte, que é separada de ajustar" do
    ator = entra_com([ Permission::BATCHES_READ, Permission::BATCHES_ADJUST ])
    @batch.update!(uploaded_by: ator)

    assert_no_difference -> { ImportBatch.count } do
      delete import_batch_path(@batch)
    end
    assert_response :forbidden

    outro = entra_com([ Permission::BATCHES_READ, Permission::BATCHES_DISCARD ],
      email: "descarta@exemplo.com")
    @batch.update!(uploaded_by: outro)

    assert_difference -> { ImportBatch.count }, -1 do
      delete import_batch_path(@batch)
    end
  end

  test "anotação: ler e escrever são chaves diferentes" do
    # O cliente precisa existir na carteira do ator: desde o recorte por escopo, anotação de
    # empresa sem EC alcançável responde 404 — e é outro assunto, testado à parte.
    canal = Channel.create!(external_id: "5555", name: "MASTER DA ANOTACAO")
    company = Company.create!(cnpj: "11222333000181")
    Establishment.create!(ec: "55000001", company:, channel: canal)

    entra_com([ Permission::NOTES_READ ], channel: canal)

    get edit_company_note_path(company)
    assert_response :success

    patch company_note_path(company), params: { body: "<div>Oi</div>" }
    assert_response :forbidden

    entra_com([ Permission::NOTES_READ, Permission::NOTES_WRITE ], email: "escreve@exemplo.com",
      channel: canal)

    patch company_note_path(company), params: { body: "<div>Oi</div>" }
    assert_response :redirect
  end

  test "super admin não precisa de chave marcada" do
    entra_com([], super_admin: true)

    get reports_path
    assert_response :success

    get metabase_path
    assert_response :success
  end

  # O menu é a primeira coisa que o usuário vê: mostrar link para tela que responde 403
  # revela o que existe a quem não pode abrir.
  test "o menu mostra só o que o ator pode abrir" do
    entra_com([ Permission::REPORTS_READ ])

    get reports_path

    assert_select "nav[aria-label='Navegação principal']" do
      assert_select "a[href=?]", reports_path
      assert_select "a[href=?]", establishments_path, count: 0
      assert_select "a[href=?]", import_batches_path, count: 0
      assert_select "a[href=?]", metabase_path, count: 0
    end
  end

  private

  def entra_com(permissions, email: "ator@exemplo.com", super_admin: false, channel: nil)
    sign_out if Current.session
    user = create_user(email:, permissions:, super_admin:)
    user.access_grants.create!(channel:) if channel
    sign_in_as(user)
  end
end
