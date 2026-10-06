require "test_helper"

# Chave sem a base não abre tela nenhuma. O convite recusa a combinação antes de a pessoa
# descobrir entrando.
class PermissionTest < ActiveSupport::TestCase
  test "toda chave ou vale sozinha ou declara a base que exige" do
    standalone = Permission::KEYS - Permission::REQUIRES.keys

    assert_equal %w[reports_revenue reports_clover reports_weekly reports_three_months
      reports_recurring reports_indicators establishments_read batches_read batches_upload
      batches_approve metabase_read users_invite].sort, standalone.sort
  end

  test "chave sem a base é recusada no usuário, com a base no motivo" do
    Permission::REQUIRES.each do |key, bases|
      user = User.new(organization: default_organization, email_address: "x@exemplo.com", name: "X",
        password: Accounts::PASSWORD, permissions: [ key ])

      assert_not user.valid?, key
      assert_match(/#{Regexp.escape(Permission.label(key))}.*#{Regexp.escape(Permission.requirement_text(key))}/,
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
    assert_equal 'requer "Faturamento" ou "Clover Capital" ou "Ver estabelecimentos"',
      Permission.requirement_text(Permission::NOTES_READ)
    assert_nil Permission.requirement_text(Permission::REPORTS_REVENUE)
  end

  # Baixar vale em qualquer tela de carteira, e a pessoa tem só as que foram marcadas.
  test "baixar exige ao menos um item do menu, qualquer um" do
    Permission::REPORT_KEYS.each do |screen|
      user = User.new(organization: default_organization, email_address: "z@exemplo.com", name: "Z",
        password: Accounts::PASSWORD, permissions: [ screen, Permission::REPORTS_EXPORT ])

      assert user.valid?, screen
    end
    assert_equal "requer ao menos um item do menu marcado", Permission.requirement_text(Permission::REPORTS_EXPORT)
  end

  test "todo item do menu de relatórios tem descrição para a tela de convite" do
    Permission::REPORT_KEYS.each { |key| assert Permission.description(key).present?, key }
  end

  # A tela trava a base marcada, e caixa travada não viaja no formulário: quem recebe
  # "Editar anotação" leva "Ver anotação" junto. Com alternativas não há o que escolher pela
  # pessoa, e nada é acrescentado.
  test "a base única vem junto com a chave que depende dela" do
    assert_equal [ Permission::NOTES_READ, Permission::NOTES_WRITE ].sort,
      Permission.with_implied([ Permission::NOTES_WRITE ]).sort
    assert_equal [ Permission::BATCHES_UPLOAD, Permission::BATCHES_DISCARD ].sort,
      Permission.with_implied([ Permission::BATCHES_DISCARD ]).sort
    assert_equal [ Permission::REPORTS_EXPORT ], Permission.with_implied([ Permission::REPORTS_EXPORT ])
  end

  private

  # A base de uma chave pode ter base própria (editar anotação → ver anotação → uma tela).
  def with_bases(key)
    bases = Permission::REQUIRES.fetch(key, [])
    return [ key ] if bases.empty?

    [ key, *with_bases(bases.first) ]
  end
end
