# O dump da produção traz o segredo do segundo fator e a senha provisória cifrados com as
# chaves AR_ENCRYPTION_* de lá, que a homologação não tem (são próprias desde 02/10/2026).
# Sem esta limpeza, o login de quem veio no dump quebra ao ler o segredo.
#
# Zera em SQL, sem carregar os registros: ler o atributo é justamente o que falha. A senha
# continua valendo (é digest, não cifra) e a homologação pede a inscrição do segundo fator de
# novo — com o código na tela, como sempre ali. Os códigos de recuperação e as sessões da
# produção saem junto: são dela, não servem aqui.
module StagingSecrets
  def self.allowed?(rails_env: Rails.env, app_environment: ENV["APP_ENVIRONMENT"])
    rails_env.to_s == "test" || app_environment == "staging"
  end

  def self.forget!
    raise "StagingSecrets só roda na homologação (APP_ENVIRONMENT=staging)." unless allowed?

    ActiveRecord::Base.transaction do
      {
        users: User.update_all(otp_secret: nil, mfa_enabled_at: nil, otp_last_used_at: nil,
          provisional_password: nil),
        recovery_codes: RecoveryCode.delete_all,
        sessions: Session.delete_all
      }
    end
  end
end
