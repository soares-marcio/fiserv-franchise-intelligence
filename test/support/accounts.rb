# Contas para a suíte. Não há fixture aqui: o projeto monta o que precisa a cada teste
# (a planilha sintética é o exemplo), e usuário segue a mesma regra — quem lê o teste vê
# qual ator ele descreve, sem procurar em outro arquivo.
#
# O login é feito **pelas rotas**, com senha e código de verdade. Injetar o cookie na mão
# seria mais rápido e testaria menos: o portão em si deixaria de ser exercitado a cada
# teste, e uma regressão no login só apareceria no teste do login.
module Accounts
  PASSWORD = "senha-de-teste-123".freeze
  # Segredo fixo: o código muda a cada 30 segundos, mas a semente não precisa variar, e um
  # valor estável deixa o teste legível.
  OTP_SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP".freeze

  # A organização de toda a suíte: Masters, lotes e contas comuns nascem nela, a menos que
  # o teste diga outra coisa. Tem nome de propósito — sem nome, o onboarding redirecionaria
  # toda requisição do administrador para a tela de nomear.
  def default_organization
    @default_organization ||= Organization.find_or_create_by!(name: "Organização de Teste")
  end

  # Ator que pode tudo **na organização padrão**: o administrador dela. É o padrão dos
  # testes que não falam de permissão: eles descrevem telas e números, não autorização.
  def admin_user(email: "chefe@exemplo.com", **atributos)
    create_user(email:, organization_admin: true, **atributos)
  end

  # A conta da plataforma: cria organizações e não vê dado nenhum.
  def platform_admin_user(email: "plataforma@exemplo.com", **atributos)
    create_user(email:, platform_admin: true, **atributos)
  end

  # Ator com recorte e permissões explícitas — para os testes que afirmam o que alguém
  # **não** pode ver ou fazer.
  def scoped_user(permissions:, channel: nil, sub_channel: nil, email: "convidado@exemplo.com", **atributos)
    user = create_user(email:, permissions:, **atributos)
    if sub_channel
      user.access_grants.create!(channel: sub_channel.channel, sub_channel:)
    elsif channel
      user.access_grants.create!(channel:)
    end
    user
  end

  def create_user(email:, name: "Teste", permissions: [], **atributos)
    # A conta da plataforma não tem organização; toda outra nasce na padrão.
    atributos = { organization: default_organization }.merge(atributos) unless atributos[:platform_admin]
    User.create!(
      email_address: email, name:, password: PASSWORD, permissions:,
      otp_secret: OTP_SECRET, mfa_enabled_at: Time.current, must_change_password: false,
      **atributos
    )
  end

  # A organização padrão inteira — o que o administrador dela enxerga.
  def escopo_da_organizacao(organization = default_organization)
    AccessScope.organization_wide(organization)
  end

  # Escopo de um Master inteiro — o que a maioria dos testes de serviço quer dizer quando
  # antes passava channel_id.
  def escopo_do_canal(channel_id)
    AccessScope.new(full_channel_ids: Array(channel_id), sub_channel_ids: [])
  end

  # Escopo de um MIC avulso, para os testes de vazamento entre MICs do mesmo Master.
  def escopo_do_mic(sub_channel)
    AccessScope.new(full_channel_ids: [], sub_channel_ids: [ sub_channel.id ])
  end

  def current_otp(user = nil)
    ROTP::TOTP.new((user&.otp_secret || OTP_SECRET)).now
  end

  # Login de verdade, em dois passos, como o usuário faz.
  def sign_in_as(user, password: PASSWORD)
    post session_path, params: { email_address: user.email_address, password: }
    post mfa_path, params: { code: current_otp(user) } if response.redirect? && mfa_pending?
    user
  end

  def sign_out
    delete session_path
  end

  private

  # O segundo passo só existe depois que o MFA entra (F3). Enquanto não existir, o helper
  # continua válido e o teste não precisa saber disso.
  def mfa_pending?
    Rails.application.routes.url_helpers.respond_to?(:mfa_path) &&
      response.location.to_s.include?("/mfa")
  end
end
