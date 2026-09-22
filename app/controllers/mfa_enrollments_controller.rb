# Inscrição do segundo fator: a tela que todo usuário vê uma vez, antes de usar o portal.
# Acontece já autenticado (a senha foi aceita e a sessão existe), porque só aqui o segredo
# pode ser mostrado — e depois dela nunca mais.
class MfaEnrollmentsController < ApplicationController
  layout "auth"

  before_action :require_pending_enrollment

  def show
    # O segredo nasce na primeira visita e sobrevive a recarregar a tela: gerar um novo a
    # cada acesso invalidaria o QR que a pessoa acabou de ler no celular.
    Current.user.update!(otp_secret: OneTimePassword.generate_secret) if Current.user.otp_secret.blank?
    @uri = OneTimePassword.new(Current.user).provisioning_uri
    @qr_code = QrCode.svg(@uri)
  end

  def create
    unless OneTimePassword.new(Current.user).verify(params[:code])
      redirect_to mfa_enrollment_path, alert: "Código inválido. Confira o horário do celular."
      return
    end

    Current.user.update!(mfa_enabled_at: Time.current)
    @codes = RecoveryCode.generate_for(Current.user)
    render :codes
  end

  private

  # Quem já inscreveu não volta aqui: repetir a inscrição trocaria o segredo e invalidaria
  # o autenticador em uso. Refazer é ação de administrador, que zera antes.
  def require_pending_enrollment
    redirect_to root_path if Current.user.mfa_enabled?
  end
end
