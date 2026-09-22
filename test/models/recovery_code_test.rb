require "test_helper"

class RecoveryCodeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "recupera@exemplo.com", name: "R", password: "senha-bem-longa-1")
  end

  test "gera dez códigos legíveis, guardados só como digest" do
    codigos = RecoveryCode.generate_for(@user)

    assert_equal RecoveryCode::HOW_MANY, codigos.size
    assert_equal RecoveryCode::HOW_MANY, @user.recovery_codes.count
    assert codigos.all? { |c| c.length == RecoveryCode::LENGTH }
    assert_empty codigos.join.chars.uniq - RecoveryCode::ALPHABET,
      "código não pode ter caractere ambíguo: o usuário copia à mão"
    guardados = @user.recovery_codes.pluck(:code_digest)
    assert_empty guardados & codigos, "o código em claro não pode estar no banco"
  end

  test "reconhece o próprio código e recusa os outros" do
    codigos = RecoveryCode.generate_for(@user)
    registro = @user.recovery_codes.first

    assert(codigos.any? { |codigo| registro.matches?(codigo) })
    assert_not registro.matches?("XXXXXXXXXX")
  end

  test "gerar de novo invalida os anteriores" do
    antigos = RecoveryCode.generate_for(@user)
    RecoveryCode.generate_for(@user)

    assert_equal RecoveryCode::HOW_MANY, @user.recovery_codes.reload.count
    assert @user.recovery_codes.none? { |registro| antigos.any? { |c| registro.matches?(c) } }
  end
end
