require "test_helper"

# Chave sem a base não abre tela nenhuma. O convite recusa a combinação antes de a pessoa
# descobrir entrando.
class PermissionTest < ActiveSupport::TestCase
  test "toda chave ou vale sozinha ou declara a base que exige" do
    standalone = Permission::KEYS - Permission::REQUIRES.keys

    assert_equal %w[reports_read establishments_read batches_read batches_upload batches_approve
      metabase_read users_invite].sort, standalone.sort
  end

  test "chave sem a base é recusada no usuário, com a base no motivo" do
    Permission::REQUIRES.each do |key, bases|
      user = User.new(organization: default_organization, email_address: "x@exemplo.com", name: "X",
        password: Accounts::PASSWORD, permissions: [ key ])

      assert_not user.valid?, key
      assert_match(/#{Regexp.escape(Permission.label(key))}.*requer.*#{Regexp.escape(Permission.label(bases.first))}/,
        user.errors[:permissions].join, key)

      user.permissions = with_bases(key)
      user.valid?
      assert_empty user.errors[:permissions], "#{key} com as bases deveria passar"
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
  def with_bases(key)
    bases = Permission::REQUIRES.fetch(key, [])
    return [ key ] if bases.empty?

    [ key, *with_bases(bases.first) ]
  end
end
