class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  # Dois limites de natureza diferente: por IP contém a varredura de uma máquina só, e por
  # e-mail contém a força bruta distribuída contra uma conta. O IP real chega ao Rails
  # mesmo atrás do túnel (X-Forwarded-For honrado), então o balde é por pessoa.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "por-ip",
    with: -> { too_many_attempts }
  rate_limit to: 5, within: 15.minutes, only: :create, name: "por-conta",
    by: -> { params[:email_address].to_s.strip.downcase }, with: -> { too_many_attempts }

  layout "auth"

  def new
  end

  def create
    user = User.authenticate_by(email_address: params[:email_address].to_s.strip.downcase,
      password: params[:password].to_s)

    return deny unless user&.active?

    start_new_session_for(user)
    redirect_to after_authentication_url
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: "Você saiu do portal."
  end

  private

  # Uma mensagem só para e-mail inexistente, senha errada e conta desativada: qualquer
  # diferença entre elas conta a quem tenta se aquele e-mail existe no portal.
  def deny
    redirect_to new_session_path(email_address: params[:email_address]),
      alert: "E-mail ou senha inválidos."
  end

  def too_many_attempts
    redirect_to new_session_path, alert: "Muitas tentativas em sequência. Tente de novo em alguns minutos."
  end
end
