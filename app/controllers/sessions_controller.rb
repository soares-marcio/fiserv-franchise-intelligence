class SessionsController < ApplicationController
  include PendingAuthentication

  # raise: false porque enquanto o portal estiver aberto não existe filtro para pular;
  # quando a exigência de login entrar, esta linha passa a valer sem precisar mudar.
  allow_unauthenticated_access only: %i[ new create ], raise: false
  # Dois limites de natureza diferente: por IP contém a varredura de uma máquina só, e por
  # e-mail contém a força bruta distribuída contra uma conta. O IP real chega ao Rails
  # mesmo atrás do túnel (X-Forwarded-For honrado), então o balde é por pessoa.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "por-ip",
    with: -> { too_many_attempts }
  rate_limit to: 5, within: 15.minutes, only: :create, name: "por-conta",
    by: -> { params[:email_address].to_s.strip.downcase }, with: -> { too_many_attempts }

  layout "auth"

  # Entrar não é uma ação autorizável: quem chega aqui ainda não tem permissões.
  skip_after_action :verify_authorized

  def new
  end

  def create
    email = params[:email_address].to_s.strip.downcase
    user = User.authenticate_by(email_address: email, password: params[:password].to_s)

    # A senha errada não diz quem errou — authenticate_by devolve nada. Sem procurar a
    # conta aqui, o contador de tentativas nunca subiria e o bloqueio seria decoração.
    # A resposta continua a mesma para conta inexistente, senha errada, conta desativada e
    # organização suspensa: dizer "suspensa" confirmaria que o e-mail existe.
    return handle_failure(email) if user.nil?
    return locked if user.locked?
    # Senha certa, conta ativa, prazo vencido: a pessoa precisa saber o que fazer, e quem
    # chegou até aqui já tem a senha. Antes do segundo fator — não há por que pedir o
    # código a quem não vai entrar (decisão de 06/10/2026).
    return access_expired(user) if user.access_expired? && user.active? && !user.organization&.suspended?
    return handle_failure(email) unless user.sign_in_allowed?

    user.register_successful_attempt!

    # Quem ainda não inscreveu o segundo fator não tem código a apresentar: a sessão nasce
    # aqui e a inscrição é a primeira tela, imposta pelo ApplicationController.
    unless user.mfa_enabled?
      start_new_session_for(user)
      Audit.record("session.start", user:, request:, metadata: { mfa: "pendente" })
      return redirect_to mfa_enrollment_path
    end

    # A senha certa ainda não é uma sessão: o segundo fator vem antes, e até ele ser
    # respondido não existe linha em sessions — não há sessão pela metade para alguém
    # esquecer de conferir.
    start_pending_authentication(user)
    redirect_to mfa_path
  end

  def destroy
    Audit.record("session.end", request:)
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: "Você saiu do portal."
  end

  private

  # Uma mensagem só para e-mail inexistente, senha errada e conta desativada: qualquer
  # diferença entre elas conta a quem tenta se aquele e-mail existe no portal.
  def handle_failure(email)
    target = User.find_by(email_address: email)
    target&.register_failed_attempt!
    # O e-mail tentado entra na trilha mesmo quando não existe conta: é o que permite ver
    # uma varredura acontecendo.
    Audit.record("session.failed", user: target, request:,
      metadata: { email_tentado: email, bloqueada: target&.locked? || false })
    deny
  end

  def access_expired(user)
    Audit.record("session.expired_access", user:, request:)
    redirect_to new_session_path(email_address: params[:email_address]),
      alert: "Seu acesso venceu em #{I18n.l(user.access_expires_on, format: '%d/%m/%Y')}. " \
        "Peça a quem administra os acessos para renová-lo."
  end

  def deny
    redirect_to new_session_path(email_address: params[:email_address]),
      alert: "E-mail ou senha inválidos."
  end

  # Mensagem própria de propósito: aqui a conta já provou existir para quem a bloqueou, e
  # esconder o motivo faria a pessoa tentar de novo até o limite seguinte.
  def locked
    redirect_to new_session_path, alert: "Conta bloqueada por tentativas seguidas. Tente mais tarde."
  end

  def too_many_attempts
    redirect_to new_session_path, alert: "Muitas tentativas em sequência. Tente de novo em alguns minutos."
  end
end
