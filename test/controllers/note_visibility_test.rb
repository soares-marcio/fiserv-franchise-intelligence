require "test_helper"

# Sem "Ver anotação", a anotação não existe para a pessoa: nem o botão "Anotar" (que abria um
# modal vazio, "Content missing", porque o servidor recusa), nem o ponto de "já tem", nem a
# marca "anotado" — os dois últimos contavam que havia anotação a quem não pode lê-la
# (homologação de 06/10/2026).
class NoteVisibilityTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  CNPJ = "11222333000181".freeze

  setup do
    import_synthetic_workbook
    @channel = Channel.find_by!(name: BinWorkbook::CHANNEL)
    @mic = SubChannel.find_by!(name: "MIC ALFA", channel: @channel)
    @company = Company.find_by!(cnpj: CNPJ)
    Operations::SaveCompanyNote.call(organization: default_organization, cnpj: CNPJ, body: "<div>Cliente pede visita.</div>")
  end

  test "sem a permissão de anotação, nenhuma tela mostra o botão nem que há anotação" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_REVENUE, Permission::ESTABLISHMENTS_READ ],
      channel: @channel))

    [ sub_channel_report_path(@mic), establishments_path, establishment_path(@company) ].each do |path|
      get path
      assert_response :success
      assert_select ".note-trigger", count: 0, text: nil
      assert_select ".note-trigger__dot", count: 0
      assert_select "th.note-col", count: 0
      assert_no_match "Cliente pede visita", response.body
    end
    get search_path(q: "ALFA")
    assert_select ".note-flag", count: 0
  end

  test "com a permissão de anotação, o botão e o ponto aparecem" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_REVENUE, Permission::ESTABLISHMENTS_READ,
      Permission::NOTES_READ ], channel: @channel))

    [ sub_channel_report_path(@mic), establishments_path, establishment_path(@company) ].each do |path|
      get path
      assert_select ".note-trigger", minimum: 1
      assert_select ".note-trigger__dot", minimum: 1
    end
  end

  # Ver sem editar mostrava o editor e o "Salvar" — que o servidor recusa. Quem só lê vê o
  # texto, e o botão diz o que faz (homologação de 06/10/2026).
  test "só com ver, o modal mostra o texto sem editor e o botão é Ver anotação" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_REVENUE, Permission::NOTES_READ ], channel: @channel))

    get sub_channel_report_path(@mic)
    assert_select ".note-trigger", text: /Ver anotação/
    assert_select ".note-trigger", text: /Anotar/, count: 0

    get edit_company_note_path(@company)
    assert_response :success
    assert_match "Cliente pede visita", response.body
    assert_select "trix-editor, form.note-form", count: 0
    assert_no_match "Salvar anotação", response.body
  end

  test "só com ver, cliente sem anotação não tem o que abrir" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_REVENUE, Permission::NOTES_READ ], channel: @channel))
    CompanyNote.delete_all

    get sub_channel_report_path(@mic)
    assert_select ".note-trigger[disabled]", minimum: 1
    assert_select ".note-trigger:not([disabled])", count: 0
  end

  test "com editar, o botão é Anotar e o modal traz o editor" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_REVENUE, Permission::NOTES_READ,
      Permission::NOTES_WRITE ], channel: @channel))

    get sub_channel_report_path(@mic)
    assert_select ".note-trigger", text: /Anotar/
    get edit_company_note_path(@company)
    assert_select "form.note-form"
    assert_match "Salvar anotação", response.body
  end
end
