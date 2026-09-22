# Este projeto não usa credentials: não há config/master.key, e os containers recebem
# SECRET_KEY_BASE por ambiente (docker-compose.yml). As chaves de criptografia seguem o
# mesmo caminho — .env no Mac e no berry, variáveis no Compose.
#
# Fora de produção valem literais fixos: o segredo que isto protege é o TOTP de usuário
# real, que só existe em produção, e depender de variável para rodar a suíte tornaria o
# teste mais frágil sem proteger nada.
Rails.application.configure do
  default = "fiserv-desenvolvimento-nao-e-segredo-0000000000"

  config.active_record.encryption.primary_key = ENV["AR_ENCRYPTION_PRIMARY_KEY"].presence || default
  config.active_record.encryption.deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"].presence || default
  config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_SALT"].presence || default

  # A guarda do SECRET_KEY_BASE_DUMMY é o que mantém o assets:precompile da imagem verde:
  # ali o Rails sobe em produção sem nenhum segredo real, só para compilar os assets.
  if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank? && ENV["AR_ENCRYPTION_PRIMARY_KEY"].blank?
    raise "Defina AR_ENCRYPTION_PRIMARY_KEY, AR_ENCRYPTION_DETERMINISTIC_KEY e AR_ENCRYPTION_SALT no .env."
  end
end
