require "application_system_test_case"

# A dependência entre permissões só existe de verdade no navegador: marcar "Editar" trava o
# "Ver" marcado, desmarcar devolve o "Ver" ao estado de antes, e o que depende de uma entre
# várias telas fica desabilitado até uma delas ser marcada (homologação de 06/10/2026).
class PermissionDependenciesTest < ApplicationSystemTestCase
  setup do
    Channel.create!(organization: default_organization, external_id: "8001", name: "MASTER A")
    visit new_user_path
  end

  test "editar marca e trava o ver, e desmarcar devolve o ver como estava" do
    check "permission_reports_revenue"
    check "permission_notes_write"

    assert_checked_field "permission_notes_read", disabled: true

    uncheck "permission_notes_write"
    assert_unchecked_field "permission_notes_read", disabled: false
  end

  test "o ver marcado antes continua marcado quando o editar sai" do
    check "permission_reports_revenue"
    check "permission_notes_read"
    check "permission_notes_write"
    uncheck "permission_notes_write"

    assert_checked_field "permission_notes_read", disabled: false
  end

  test "ver anotação e baixar ficam desabilitados até uma tela ser marcada" do
    assert_unchecked_field "permission_notes_read", disabled: true
    assert_unchecked_field "permission_reports_export", disabled: true

    check "permission_reports_clover"
    assert_unchecked_field "permission_notes_read", disabled: false
    check "permission_notes_read"
    check "permission_reports_export"

    uncheck "permission_reports_clover"
    assert_unchecked_field "permission_notes_read", disabled: true
    assert_unchecked_field "permission_reports_export", disabled: true
  end
end
