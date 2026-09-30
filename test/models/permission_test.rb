require "test_helper"

# Chave sem a base não abre tela nenhuma. O convite recusa a combinação antes de a pessoa
# descobrir entrando.
class PermissionTest < ActiveSupport::TestCase
  test "toda chave ou vale sozinha ou declara a base que exige" do
    sozinhas = Permission::KEYS - Permission::REQUIRES.keys

    assert_equal %w[reports_read establishments_read batches_read batches_upload batches_approve
      metabase_read users_invite].sort, sozinhas.sort
  end

  test "chave sem a base é recusada no usuário, com a base no motivo" do
    Permission::REQUIRES.each do |chave, bases|
      user = User.new(organization: default_organization, email_address: "x@exemplo.com", name: "X",
        password: Accounts::PASSWORD, permissions: [ chave ])

      assert_not user.valid?, chave
      assert_match(/#{Regexp.escape(Permission.label(chave))}.*requer.*#{Regexp.escape(Permission.label(bases.first))}/,
        user.errors[:permissions].join, chave)

      user.permissions = com_as_bases(chave)
      user.valid?
      assert_empty user.errors[:permissions], "#{chave} com as bases deveria passar"
    end
  end

  test "basta uma das alternativas" do
    user = User.new(organization: default_organization, email_address: "y@exemplo.com", name: "Y",
      password: Accounts::PASSWORD, permissions: [ Permission::ESTABLISHMENTS_READ, Permission::NOTES_READ ])

    assert user.valid?
    assert_equal 'requer "Ver relatórios" ou "Ver estabelecimentos"', Permission.requirement_text(Permission::NOTES_READ)
    assert_nil Permission.requirement_text(Permission::REPORTS_READ)
  end

  private

  # A base de uma chave pode ter base própria (editar anotação → ver anotação → uma tela).
  def com_as_bases(chave)
    bases = Permission::REQUIRES.fetch(chave, [])
    return [ chave ] if bases.empty?

    [ chave, *com_as_bases(bases.first) ]
  end
end
