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

  # Ator que pode tudo. É o padrão dos testes que não falam de permissão: eles descrevem
  # telas e números, não autorização.
  def admin_user(email: "chefe@exemplo.com", **atributos)
    create_user(email:, super_admin: true, **atributos)
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
    User.create!(
      email_address: email, name:, password: PASSWORD, permissions:,
      otp_secret: OTP_SECRET, mfa_enabled_at: Time.current, must_change_password: false,
      **atributos
    )
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
