require "test_helper"

# O seed roda a cada execução da suíte (schema_integrity_test o chama) e no primeiro
# db:prepare de produção. As duas coisas precisam ser verdade ao mesmo tempo: criar o
# administrador quando as variáveis existem, e não criar nada quando não existem.
class AdminSeedTest < ActiveSupport::TestCase
  setup do
    @antes = ENV.slice("ADMIN_EMAIL", "ADMIN_PASSWORD", "ADMIN_NAME")
    %w[ADMIN_EMAIL ADMIN_PASSWORD ADMIN_NAME].each { |chave| ENV.delete(chave) }
  end

  teardown do
    %w[ADMIN_EMAIL ADMIN_PASSWORD ADMIN_NAME].each { |chave| ENV.delete(chave) }
    @antes.each { |chave, valor| ENV[chave] = valor }
  end

  test "sem as variáveis, o seed não cria usuário nenhum" do
    assert_no_difference -> { User.count } do
      Rails.application.load_seed
    end
  end

  test "com as variáveis, cria o administrador com as duas pendências do primeiro acesso" do
    ENV["ADMIN_EMAIL"] = "Chefe@Exemplo.com "
    ENV["ADMIN_PASSWORD"] = "senha-do-env-1234"
    ENV["ADMIN_NAME"] = "Chefe"

    assert_difference -> { User.count } do
      Rails.application.load_seed
    end

    admin = User.find_by(email_address: "chefe@exemplo.com")
    assert admin.platform_admin?
    assert admin.must_change_password?, "a senha do .env passou por arquivo: troca no primeiro acesso"
    assert_not admin.mfa_enabled?, "o segundo fator é cadastrado pela própria pessoa"
    assert admin.authenticate("senha-do-env-1234")
  end

  # Senha curta no .env aconteceu na homologação de 28/09/2026: o seed morria com
  # "Translation missing" e não dizia qual variável estava errada.
  test "senha curta no .env aborta dizendo o motivo, sem repetir a senha" do
    ENV["ADMIN_EMAIL"] = "chefe@exemplo.com"
    ENV["ADMIN_PASSWORD"] = "curta12"

    erro = assert_raises(SystemExit) { Rails.application.load_seed }

    assert_match(/8 caracteres/, erro.message)
    assert_no_match(/curta12/, erro.message)
    assert_nil User.find_by(email_address: "chefe@exemplo.com")
  end

  # Rodar de novo não pode criar um segundo administrador nem reescrever a senha de quem já
  # trocou — o seed roda em todo db:prepare.
  test "rodar duas vezes não duplica nem reverte a troca de senha" do
    ENV["ADMIN_EMAIL"] = "chefe@exemplo.com"
    ENV["ADMIN_PASSWORD"] = "senha-do-env-1234"
    Rails.application.load_seed

    admin = User.find_by!(email_address: "chefe@exemplo.com")
    admin.update!(password: "senha-escolhida-pela-pessoa", must_change_password: false)

    assert_no_difference -> { User.count } do
      Rails.application.load_seed
    end

    assert admin.reload.authenticate("senha-escolhida-pela-pessoa"),
      "o seed não pode devolver a senha do .env para quem já escolheu a sua"
    assert_not admin.must_change_password?
  end
end
