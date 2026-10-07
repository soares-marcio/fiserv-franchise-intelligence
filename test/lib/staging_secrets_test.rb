require "test_helper"

class StagingSecretsTest < ActiveSupport::TestCase
  # O que chega da produção foi cifrado com as chaves AR_ENCRYPTION_* de lá; a homologação
  # tem as dela e não decifra nada. Gravar texto que nenhuma chave daqui abre reproduz isso.
  test "zera segundo fator, senha provisória, códigos e sessões, mesmo sem decifrar" do
    user = admin_user
    RecoveryCode.generate_for(user)
    user.sessions.create!(user_agent: "teste", ip_address: "10.0.0.1", last_active_at: Time.current)
    other_keys = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("chave-da-producao")
    ciphertexts = ActiveRecord::Encryption.with_encryption_context(key_provider: other_keys) do
      %i[otp_secret provisional_password].index_with { |name| User.type_for_attribute(name).serialize("da-producao") }
    end
    # Em forma de string o update_all não passa pelo tipo do atributo, que cifraria de novo.
    User.where(id: user.id).update_all([ "otp_secret = ?, provisional_password = ?", *ciphertexts.values ])
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) { User.find(user.id).otp_secret }

    StagingSecrets.forget!

    user = User.find(user.id)
    assert_nil user.otp_secret
    assert_nil user.provisional_password
    assert_nil user.mfa_enabled_at
    assert_not user.mfa_enabled?, "no próximo login a homologação pede a inscrição de novo"
    assert_empty user.recovery_codes
    assert_empty user.sessions
    assert user.authenticate(Accounts::PASSWORD), "a senha não é cifrada pelas chaves e continua valendo"
  end

  test "só roda na homologação e nos testes, nunca na produção" do
    assert StagingSecrets.allowed?(rails_env: "production", app_environment: "staging")
    assert StagingSecrets.allowed?(rails_env: "test", app_environment: nil)
    assert_not StagingSecrets.allowed?(rails_env: "production", app_environment: nil)
    assert_not StagingSecrets.allowed?(rails_env: "production", app_environment: "")
  end
end
