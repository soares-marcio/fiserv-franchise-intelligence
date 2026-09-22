# O segundo fator do portal: TOTP de 30 segundos, o que qualquer autenticador (Google
# Authenticator, 1Password, Authy) entende.
#
# Duas defesas importam aqui e ficam neste arquivo, não espalhadas pelos controllers:
# o código não vale duas vezes (`after:`) e a janela anterior é aceita (`drift_behind`),
# porque relógio de celular atrasa e o usuário digita no fim do intervalo.
class OneTimePassword
  ISSUER = "Melo Pay — Auditoria BIN".freeze
  DRIFT = 15

  def self.generate_secret = ROTP::Base32.random

  def initialize(user)
    @user = user
  end

  def provisioning_uri
    totp.provisioning_uri(@user.email_address)
  end

  # Devolve true e carimba o instante aceito. O carimbo é o que impede reutilizar o mesmo
  # código dentro da janela — quem o interceptar na tela não o usa depois.
  def verify(code)
    aceito = totp.verify(code.to_s.strip, after: @user.otp_last_used_at&.to_i, drift_behind: DRIFT)
    return false unless aceito

    @user.update_column(:otp_last_used_at, Time.at(aceito).utc)
    true
  end

  private

  def totp
    @totp ||= ROTP::TOTP.new(@user.otp_secret, issuer: ISSUER)
  end
end
