require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normaliza o e-mail e recusa duplicado com outra caixa" do
    User.create!(email_address: " Chefe@Exemplo.com ", name: "Chefe", password: "senha-bem-longa-1")

    assert_equal "chefe@exemplo.com", User.last.email_address
    duplicado = User.new(email_address: "CHEFE@exemplo.com", name: "Outro", password: "senha-bem-longa-1")

    assert_not duplicado.valid?
  end

  # O portal passa a ser alcançável pela internet sem o Access na frente: a senha deixa de
  # ser a segunda barreira e vira a primeira.
  test "recusa senha curta" do
    user = User.new(email_address: "a@exemplo.com", name: "A", password: "curta1")

    assert_not user.valid?
    assert_includes user.errors[:password].join, "12"
  end

  test "permissão fora do catálogo não passa nem pelo model nem pelo banco" do
    user = User.new(email_address: "b@exemplo.com", name: "B", password: "senha-bem-longa-1",
      permissions: [ Permission::REPORTS_READ, "inventada" ])

    assert_not user.valid?
    assert_match(/inventada/, user.errors[:permissions].join)
  end

  # Super admin não recebe chave a chave: guardar a lista inteira nele criaria dois lugares
  # para acrescentar permissão nova, e um deles seria esquecido.
  test "super admin tem toda permissão sem nenhuma marcada" do
    chefe = User.new(super_admin: true, permissions: [])
    comum = User.new(permissions: [ Permission::REPORTS_READ ])

    assert chefe.permitted?(Permission::BATCHES_DISCARD)
    assert comum.permitted?(Permission::REPORTS_READ)
    assert_not comum.permitted?(Permission::BATCHES_DISCARD)
  end

  test "o segredo do TOTP não fica legível no banco" do
    user = User.create!(email_address: "c@exemplo.com", name: "C", password: "senha-bem-longa-1",
      otp_secret: "JBSWY3DPEHPK3PXP")

    cru = User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{user.id}")

    assert_equal "JBSWY3DPEHPK3PXP", user.reload.otp_secret
    assert_not_equal "JBSWY3DPEHPK3PXP", cru
    assert_no_match(/JBSWY3DPEHPK3PXP/, cru)
  end
end
