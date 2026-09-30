require "test_helper"

# Administração de acessos. Quase todos os testes aqui são sobre a mesma coisa: impedir que
# alguém conceda — a outro ou a si — mais do que recebeu.
class UsersControllerTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @canal_a = Channel.create!(organization: default_organization, external_id: "8001", name: "MASTER A")
    @canal_b = Channel.create!(organization: default_organization, external_id: "8002", name: "MASTER B")
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

  # Os papéis de administração não se concedem pelo convite: a plataforma nasce do seed e
  # o administrador da organização, da própria plataforma. Parâmetro forjado é ignorado.
  test "administrador da organização não nomeia plataforma nem outro administrador pelo convite" do
    alvo = scoped_user(permissions: [ Permission::REPORTS_READ ], channel: @canal_a, email: "alvo@exemplo.com")
    sign_in_as(admin_user)

    patch user_path(alvo), params: {
      user: { name: alvo.name, email_address: alvo.email_address, platform_admin: "1", organization_admin: "1" },
      permissions: [], grants: {}
    }

    assert_not alvo.reload.platform_admin?
    assert_not alvo.organization_admin?
  end

  test "delegado não nomeia plataforma: o parâmetro é ignorado" do
    delegado = scoped_user(permissions: [ Permission::USERS_INVITE ], channel: @canal_a, email: "delegado@exemplo.com")
    sign_in_as(delegado)

    post users_path, params: {
      user: { name: "Novo", email_address: "novo@exemplo.com", platform_admin: "1" }, permissions: [], grants: {}
    }

    assert_not User.find_by(email_address: "novo@exemplo.com").platform_admin?
  end

  # Um administrador da organização não edita outro: quem mexe neles é a plataforma.
  test "administrador da organização não edita outro administrador" do
    outro = admin_user(email: "outro@exemplo.com")
    sign_in_as(admin_user)

    patch user_path(outro), params: { user: { name: "Invadido" }, permissions: [], grants: {} }

    # 403, e não 404: o outro administrador aparece na listagem da organização — o que
    # não existe é o direito de editá-lo.
    assert_response :forbidden
    assert_equal "Teste", outro.reload.name
  end

  test "o último administrador da plataforma ativo não é rebaixado nem desativado" do
    plataforma = platform_admin_user(name: "Operadora Plataforma")

    # Pela tela ninguém o alcança; a guarda do modelo é o que vale por console.
    erro = assert_raises(ActiveRecord::RecordInvalid) { plataforma.update!(platform_admin: false) }
    assert_match(/ao menos um administrador da plataforma/, erro.message)
    assert_raises(ActiveRecord::RecordInvalid) { plataforma.update!(deactivated_at: Time.current) }
    assert plataforma.reload.platform_admin?
    assert plataforma.active?
  end

  # A listagem virou cards com o uso de cada pessoa, tirado da trilha.
  test "os cards mostram último acesso, entradas, exportações e envios" do
    chefe = admin_user
    alvo = scoped_user(permissions: [ Permission::REPORTS_READ ], channel: @canal_a, email: "alvo@exemplo.com",
      created_by: chefe)
    AuditEvent.create!(user: alvo, actor_email: alvo.email_address, action: "session.start", created_at: 2.days.ago)
    AuditEvent.create!(user: alvo, actor_email: alvo.email_address, action: "report.export", created_at: 1.day.ago)
    AuditEvent.create!(user: alvo, actor_email: alvo.email_address, action: "report.export", created_at: 40.days.ago)
    sign_in_as(chefe)

    get users_path

    assert_select ".user-card", text: /alvo@exemplo\.com/ do
      assert_select "dd", text: /#{Regexp.escape(2.days.ago.strftime("%d/%m/%Y"))}/
      assert_select "dt", text: "Exportações"
    end
    card = css_select(".user-card").find { |c| c.text.include?("alvo@exemplo.com") }
    assert_match(/Exportações\s*1\b/, card.text.squish, "a exportação de 40 dias atrás fica fora da janela")
    assert_match(/Entradas\s*1\b/, card.text.squish)
    assert_match(/Convidado por/, card.text)
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

  # Quem ainda não tem Master nem MIC não tem o que conceder: o dono de carteira própria só
  # convida depois de importar a carteira.
  test "com a chave de convidar mas sem escopo, o convite não abre" do
    sign_in_as(scoped_user(permissions: [ Permission::USERS_INVITE ], email: "vazio@exemplo.com"))

    get users_path
    assert_response :success

    get new_user_path
    assert_response :forbidden

    post users_path, params: { user: { name: "X", email_address: "x@exemplo.com" }, permissions: [], grants: {} }
    assert_response :forbidden
  end

  test "o card e a ficha destacam o administrador da organização" do
    sign_in_as(admin_user)

    get users_path
    assert_select ".user-card .badge", text: "Administrador"

    get user_path(User.find_by!(email_address: "chefe@exemplo.com"))
    assert_match(/Administrador da organização: tudo/, response.body)
  end

  test "sem a chave de administração, a tela nem abre" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_READ ], email: "comum@exemplo.com"))

    get users_path
    assert_response :forbidden

    get new_user_path
    assert_response :forbidden
  end

  # Na homologação de 28/09/2026 o convite deu 500: o formulário mandava o channel_id de
  # cada linha de MIC, marcada ou não, e cada linha desmarcada virava "Master inteiro" — a
  # segunda estourava o índice único, e sem o índice o convidado receberia o Master que
  # ninguém marcou. Agora a linha do MIC manda só o MIC, e o Master dele vem do banco.
  test "marcar um MIC manda só o MIC, e o Master dele é resolvido no servidor" do
    outro_mic = SubChannel.create!(channel: @canal_a, name: "MIC A2")
    sign_in_as(admin_user)

    post users_path, params: {
      user: { name: "Novo", email_address: "novo@exemplo.com" },
      permissions: [],
      grants: { "0_0" => { sub_channel_id: @mic_a.id } }
    }

    novo = User.find_by(email_address: "novo@exemplo.com")
    assert_equal [ [ @canal_a.id, @mic_a.id ] ], novo.access_grants.pluck(:channel_id, :sub_channel_id)
    assert_not_includes novo.access_grants.pluck(:sub_channel_id), outro_mic.id
  end

  # O flash some em segundos; a listagem é onde quem convidou vai buscar a senha para
  # entregar. Ela vale até a troca — e a troca a apaga, deixando o registro de que a pessoa
  # entrou.
  test "a senha provisória fica na listagem até a pessoa trocá-la" do
    sign_in_as(admin_user)
    post users_path, params: {
      user: { name: "Convidada", email_address: "convidada@exemplo.com" }, permissions: [], grants: {}
    }
    convidada = User.find_by(email_address: "convidada@exemplo.com")
    senha = convidada.provisional_password
    assert_equal 14, senha.length

    get users_path
    assert_select "code", text: senha
    assert_select ".user-card", text: /Senha provisória/

    convidada.update!(password: "definitiva-123456", must_change_password: false)

    get users_path
    assert_select "code", text: senha, count: 0
    assert_no_match senha, response.body
    assert_select ".user-card", text: /Entrou e trocou a senha/
  end

  # Ver a listagem é mais amplo do que editar: o delegado enxerga quem está no escopo dele,
  # mas a senha de quem tem mais do que ele não é dele para ler.
  test "a senha provisória não aparece a quem não pode editar o acesso" do
    chefe = admin_user(email: "chefe@exemplo.com")
    sign_in_as(chefe)
    post users_path, params: {
      user: { name: "Gestora", email_address: "gestora@exemplo.com" },
      permissions: [ Permission::USERS_INVITE, Permission::BATCHES_UPLOAD, Permission::BATCHES_DISCARD ],
      grants: { "0" => { channel_id: @canal_a.id } }
    }
    gestora = User.find_by(email_address: "gestora@exemplo.com")
    senha = gestora.provisional_password
    sign_out

    delegado = scoped_user(permissions: [ Permission::USERS_INVITE ], channel: @canal_a,
      email: "delegado@exemplo.com")
    sign_in_as(delegado)
    get users_path

    assert_select ".user-card", text: /Gestora/
    assert_no_match senha, response.body
  end

  # A metade do bug que fica na tela: nenhum campo oculto viaja com as caixas de MIC.
  test "o formulário de convite não manda o Master junto com cada MIC" do
    SubChannel.create!(channel: @canal_a, name: "MIC A2")
    sign_in_as(admin_user)

    get new_user_path

    assert_select "input[type=hidden][name^='grants[']", count: 0
    assert_select "input[type=checkbox][name='grants[0][channel_id]']", count: 1
    assert_select "input[type=checkbox][name$='[sub_channel_id]']", minimum: 2
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

  test "a ficha de acesso tem Voltar para a listagem" do
    sign_in_as(admin_user)
    alvo = create_user(email: "ficha@exemplo.com")

    get user_path(alvo)

    assert_select "a.breadcrumb-back[href=?]", users_path, text: /Voltar/
    get users_path
    assert_select "a.breadcrumb-back", count: 0
  end

  test "o card diz quem convidou dentro da organização, e só 'pela plataforma' quando foi ela" do
    plataforma = platform_admin_user(name: "Operadora Plataforma")
    chefe = admin_user
    chefe.update!(created_by: plataforma)
    convidado = create_user(email: "convidado@exemplo.com", created_by: chefe)
    sign_in_as(chefe)

    get users_path

    assert_match(/Criado pela plataforma em/, response.body)
    assert_no_match(/#{plataforma.name}/, response.body)
    assert_match(/Convidado por #{chefe.name} em/, response.body)
    assert_includes response.body, convidado.email_address
  end
end
