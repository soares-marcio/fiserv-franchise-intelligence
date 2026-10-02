require "test_helper"

class RecoveryCodeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(organization: default_organization, email_address: "recupera@exemplo.com", name: "R", password: "senha-bem-longa-1")
  end

  test "gera dez códigos legíveis, guardados só como digest" do
    codes = RecoveryCode.generate_for(@user)

    assert_equal RecoveryCode::HOW_MANY, codes.size
    assert_equal RecoveryCode::HOW_MANY, @user.recovery_codes.count
    assert codes.all? { |c| c.length == RecoveryCode::LENGTH }
    assert_empty codes.join.chars.uniq - RecoveryCode::ALPHABET,
      "código não pode ter caractere ambíguo: o usuário copia à mão"
    stored = @user.recovery_codes.pluck(:code_digest)
    assert_empty stored & codes, "o código em claro não pode estar no banco"
  end

  test "reconhece o próprio código e recusa os outros" do
    codes = RecoveryCode.generate_for(@user)
    record_entry = @user.recovery_codes.first

    assert(codes.any? { |code| record_entry.matches?(code) })
    assert_not record_entry.matches?("XXXXXXXXXX")
  end

  test "gerar de novo invalida os anteriores" do
    old_ones = RecoveryCode.generate_for(@user)
    RecoveryCode.generate_for(@user)

    assert_equal RecoveryCode::HOW_MANY, @user.recovery_codes.reload.count
    assert @user.recovery_codes.none? { |record_entry| old_ones.any? { |c| record_entry.matches?(c) } }
  end
end
