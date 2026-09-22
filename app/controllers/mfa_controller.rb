# Desafio do segundo fator: a tela entre a senha e o portal.
class MfaController < ApplicationController
  include PendingAuthentication

  allow_unauthenticated_access
  layout "auth"

  # O código tem seis dígitos e vale trinta segundos: sem limite, dá para varrer o espaço
  # inteiro em minutos. O limite por conta vem junto, em User#failed_attempts.
  rate_limit to: 10, within: 5.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Muitas tentativas. Entre de novo." }

  before_action :require_pending_user

  def show
    @recovery_codes_left = @user.unused_recovery_codes.count
  end

  def create
    if verify_second_factor
      @user.update!(failed_attempts: 0, locked_until: nil)
      destino = pending_return_to
      clear_pending_authentication
      start_new_session_for(@user)
      # Depois do reset_session da sessão nova: antes dele, o destino seria apagado.
      session[:return_to_after_authenticating] = destino if destino
      redirect_to after_authentication_url
    else
      register_failure
    end
  end

  private

  def require_pending_user
    @user = pending_user
    return if @user

    redirect_to new_session_path, alert: "A verificação expirou. Entre de novo."
  end

  # O mesmo campo aceita o código do autenticador e um código de recuperação: quem perdeu o
  # celular não precisa descobrir outra tela para voltar.
  def verify_second_factor
    return true if OneTimePassword.new(@user).verify(params[:code])

    spend_recovery_code
  end

  def spend_recovery_code
    codigo = @user.unused_recovery_codes.find { |registro| registro.matches?(params[:code]) }
    return false unless codigo

    codigo.update!(used_at: Time.current)
    flash[:notice] = "Código de recuperação usado. Restam #{@user.unused_recovery_codes.count}."
    true
  end

  def register_failure
    @user.increment!(:failed_attempts)
    if @user.failed_attempts >= User::MAX_FAILED_ATTEMPTS
      @user.update!(locked_until: User::LOCK_PERIOD.from_now, failed_attempts: 0)
      clear_pending_authentication
      return redirect_to new_session_path, alert: "Conta bloqueada por #{User::LOCK_PERIOD.inspect}."
    end

    redirect_to mfa_path, alert: "Código inválido."
  end
end
