require "test_helper"

# Cada chave, com o menor conjunto que a acompanha, abre a rota que promete. Uma chave
# concedida que não chega a tela nenhuma é convite quebrado — foi o caso de "Enviar
# planilha" sozinha, que não abria a tela de importação (homologação de 30/09/2026).
class PermissionRoutesTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @canal = Channel.find_by!(name: BinWorkbook::CANAL)
    @company = Company.joins(:establishments).where(establishments: { channel_id: @canal.id }).first
  end

  test "Ver relatórios abre os relatórios e o menu" do
    entra_com(Permission::REPORTS_READ)

    get reports_path
    assert_response :success
    assert_select "nav.primary-nav a[href=?]", reports_path
    get three_months_reports_path(format: :csv)
    assert_response :forbidden, "exportar é outra chave"
  end

  test "Exportar relatórios, com Ver relatórios, baixa o CSV" do
    entra_com(Permission::REPORTS_READ, Permission::REPORTS_EXPORT)

    get three_months_reports_path(format: :csv)
    assert_response :success
  end

  test "Ver estabelecimentos abre a lista, a ficha e a busca" do
    entra_com(Permission::ESTABLISHMENTS_READ)

    get establishments_path
    assert_response :success
    get establishment_path(@company)
    assert_response :success
    get search_path(q: BinWorkbook::CANAL[0, 4])
    assert_response :success
  end

  test "Ver e editar anotação, com uma tela de carteira, abrem a anotação" do
    entra_com(Permission::ESTABLISHMENTS_READ, Permission::NOTES_READ, Permission::NOTES_WRITE)

    get edit_company_note_path(@company)
    assert_response :success
  end

  test "Ver lotes abre a tela de importação e o menu" do
    entra_com(Permission::BATCHES_READ)

    get import_batches_path
    assert_response :success
    assert_select "nav.primary-nav a[href=?]", import_batches_path
  end

  test "Enviar planilha sozinha abre a tela de importação com o formulário de envio" do
    entra_com(Permission::BATCHES_UPLOAD)

    get import_batches_path
    assert_response :success
    assert_select "nav.primary-nav a[href=?]", import_batches_path
    assert_select "form[action=?]", import_batches_path
  end

  test "Reprocessar e Descartar, com Enviar planilha, agem sobre o próprio envio" do
    user = entra_com(Permission::BATCHES_UPLOAD, Permission::BATCHES_ADJUST, Permission::BATCHES_DISCARD)
    proprio = ImportBatch.create!(source_filename: "meu.xlsx", file_checksum: "meu-1", status: "failed",
      channel: @canal, uploaded_by: user)

    get import_batch_path(proprio)
    assert_response :success
    policy = ImportBatchPolicy.new(user, proprio)
    assert policy.reprocess?
    assert policy.destroy?
  end

  test "Aprovar importação sozinha abre a tela de importação com o que está em revisão" do
    entra_com(Permission::BATCHES_APPROVE)
    em_revisao = ImportBatch.create!(source_filename: "revisar.xlsx", file_checksum: "rev-1",
      status: "pending_review", channel: @canal, uploaded_by: admin_user)

    get import_batches_path
    assert_response :success
    assert_match(/revisar\.xlsx/, response.body)
    get import_batch_path(em_revisao)
    assert_response :success
  end

  test "Convidar abre os acessos" do
    entra_com(Permission::USERS_INVITE)

    get users_path
    assert_response :success
  end

  private

  # O Master inteiro, porque enviar e aprovar exigem a carteira toda.
  def entra_com(*chaves)
    user = scoped_user(permissions: chaves, channel: @canal, email: "chave@exemplo.com")
    sign_in_as(user)
    user
  end
end
