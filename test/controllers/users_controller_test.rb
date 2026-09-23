require "test_helper"

# Administração de acessos. Quase todos os testes aqui são sobre a mesma coisa: impedir que
# alguém conceda — a outro ou a si — mais do que recebeu.
class UsersControllerTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @canal_a = Channel.create!(external_id: "8001", name: "MASTER A")
    @canal_b = Channel.create!(external_id: "8002", name: "MASTER B")
    @mic_a = SubChannel.create!(channel: @canal_a, name: "MIC A1")
    @mic_b = SubChannel.create!(channel: @canal_b, name: "MIC B1")
  end

  test "convidar cria com senha provisória, troca obrigatória e sem segundo fator" do
    sign_in_as(admin_user)

    assert_difference -> { User.count } do
      post users_path, params: {
        user: { name: "Convidada", email_address: "convidada@exemplo.com" },
        permissions: [ Permission::REPORTS_READ ],
        grants: { "0" => { channel_id: @canal_a.id } }
      }
    end

    novo = User.find_by(email_address: "convidada@exemplo.com")
    assert novo.must_change_password?, "a senha provisória precisa ser trocada no primeiro acesso"
    assert_not novo.mfa_enabled?, "o segundo fator é cadastrado pela própria pessoa"
    assert_equal [ Permission::REPORTS_READ ], novo.permissions
    assert_equal [ @canal_a.id ], novo.access_grants.pluck(:channel_id)
    assert_match(/Senha provisória/, flash[:notice])
  end

  test "a senha provisória não é escolhida por quem convida" do
    sign_in_as(admin_user)

    post users_path, params: {
      user: { name: "X", email_address: "x@exemplo.com", password: "senha-escolhida-123" },
      permissions: [], grants: {}
    }

    novo = User.find_by(email_address: "x@exemplo.com")
    assert_not novo.authenticate("senha-escolhida-123"),
      "a senha vem do sistema; aceitar a do formulário deixaria quem convida entrar como a pessoa"
  end

  # O delegado é o caso que mais importa: ele administra, mas dentro do que tem.
  test "delegado não concede permissão que não possui" do
    delegado = scoped_user(permissions: [ Permission::USERS_INVITE, Permission::REPORTS_READ ],
      channel: @canal_a, email: "delegado@exemplo.com")
    sign_in_as(delegado)

    post users_path, params: {
      user: { name: "Novo", email_address: "novo@exemplo.com" },
      permissions: [ Permission::REPORTS_READ, Permission::BATCHES_DISCARD ],
      grants: { "0" => { channel_id: @canal_a.id } }
    }

    novo = User.find_by(email_address: "novo@exemplo.com")
    assert_equal [ Permission::REPORTS_READ ], novo.permissions,
      "descartar lote não estava com o delegado, então não pode ser concedido"
  end

  test "delegado não concede Master fora do próprio escopo" do
    delegado = scoped_user(permissions: [ Permission::USERS_INVITE ], channel: @canal_a,
      email: "delegado@exemplo.com")
    sign_in_as(delegado)

    post users_path, params: {
      user: { name: "Novo", email_address: "novo@exemplo.com" },
      permissions: [],
      grants: { "0" => { channel_id: @canal_a.id }, "1" => { channel_id: @canal_b.id } }
    }

    novo = User.find_by(email_address: "novo@exemplo.com")
    assert_equal [ @canal_a.id ], novo.access_grants.pluck(:channel_id)
  end

  # Quem tem só um MIC não pode conceder o Master inteiro dele.
  test "quem tem um MIC concede aquele MIC, não o Master" do
    delegado = scoped_user(permissions: [ Permission::USERS_INVITE ], sub_channel: @mic_a,
      email: "domic@exemplo.com")
    sign_in_as(delegado)

    post users_path, params: {
      user: { name: "Novo", email_address: "novo@exemplo.com" },
      permissions: [],
      grants: { "0" => { channel_id: @canal_a.id },
                "1" => { channel_id: @canal_a.id, sub_channel_id: @mic_a.id } }
    }

    novo = User.find_by(email_address: "novo@exemplo.com")
    assert_equal [ [ @canal_a.id, @mic_a.id ] ], novo.access_grants.pluck(:channel_id, :sub_channel_id)
  end

  # Sem esta regra, um admin de um MIC reiniciaria o segundo fator do super admin e entraria
  # como ele.
  test "delegado não edita nem reinicia o segundo fator de quem tem mais" do
    chefe = admin_user(email: "chefe@exemplo.com")
    delegado = scoped_user(permissions: [ Permission::USERS_INVITE ], channel: @canal_a,
      email: "delegado@exemplo.com")
    sign_in_as(delegado)

    patch user_path(chefe), params: { user: { name: "Invadido" }, permissions: [], grants: {} }
    assert_response :not_found

    post reset_mfa_user_path(chefe)
    assert_response :not_found
    assert chefe.reload.mfa_enabled?
  end

  test "ninguém desativa a si mesmo" do
    chefe = admin_user
    sign_in_as(chefe)

    post deactivate_user_path(chefe)

    assert_response :forbidden
    assert chefe.reload.active?
  end

  test "mudar permissão derruba as sessões de quem foi alterado" do
    alvo = scoped_user(permissions: [ Permission::REPORTS_READ ], channel: @canal_a,
      email: "alvo@exemplo.com")
    alvo.sessions.create!(last_active_at: Time.current)
    sign_in_as(admin_user)

    assert_difference -> { alvo.sessions.count }, -1 do
      patch user_path(alvo), params: {
        user: { name: alvo.name, email_address: alvo.email_address },
        permissions: [], grants: { "0" => { channel_id: @canal_a.id } }
      }
    end
  end

  test "desativar derruba as sessões abertas" do
    alvo = scoped_user(permissions: [], channel: @canal_a, email: "alvo@exemplo.com")
    alvo.sessions.create!(last_active_at: Time.current)
    sign_in_as(admin_user)

    post deactivate_user_path(alvo)

    assert_not alvo.reload.active?
    assert_equal 0, alvo.sessions.count
  end

  test "sem a chave de administração, a tela nem abre" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_READ ], email: "comum@exemplo.com"))

    get users_path
    assert_response :forbidden

    get new_user_path
    assert_response :forbidden
  end

  # Conceder o Master inteiro torna a concessão de MIC redundante — e escopo com recorte
  # que não recorta nada é convite a erro de leitura depois.
  test "Master inteiro apaga as concessões de MIC do mesmo Master" do
    sign_in_as(admin_user)

    post users_path, params: {
      user: { name: "Novo", email_address: "novo@exemplo.com" },
      permissions: [],
      grants: { "0" => { channel_id: @canal_a.id },
                "1" => { channel_id: @canal_a.id, sub_channel_id: @mic_a.id } }
    }

    novo = User.find_by(email_address: "novo@exemplo.com")
    assert_equal [ [ @canal_a.id, nil ] ], novo.access_grants.pluck(:channel_id, :sub_channel_id)
  end
end
