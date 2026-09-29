# Roda uma vez no primeiro `db:prepare` de um banco novo (produção inclusive) e é idempotente.
# O structure.sql não carrega role nem GRANT, e a migration que cria o metabase_ro não roda em
# banco carregado do arquivo — sem isto, produção nasceria sem acesso do Metabase.
MetabaseRole.ensure!

# Primeiro administrador. O portal exige login, então um banco novo sem nenhum usuário é um
# portal em que ninguém entra — nem para criar o primeiro acesso.
#
# No-op sem as variáveis, e isso é obrigatório: test/db/schema_integrity_test.rb roda o seed
# a cada execução da suíte, e um administrador aparecendo ali contaminaria os testes.
email = ENV["ADMIN_EMAIL"].presence
password = ENV["ADMIN_PASSWORD"].presence

if email && password
  begin
    User.find_or_create_by!(email_address: email.strip.downcase) do |user|
      user.name = ENV.fetch("ADMIN_NAME", "Administrador")
      user.password = password
      user.platform_admin = true
      # As duas pendências valem no primeiro acesso: a senha do .env passou por arquivo e por
      # quem o escreveu, e o segundo fator ainda não existe.
      user.must_change_password = true
    end
  rescue ActiveRecord::RecordInvalid => e
    # A mensagem padrão sai como "Translation missing" e não diz qual variável está errada.
    # As mensagens de validação não repetem o valor da senha — só o motivo.
    abort("[seed] administrador não criado: #{e.record.errors.full_messages.join('; ')}")
  end
  Rails.logger.info("[seed] administrador #{email} disponível para o primeiro acesso")
end
