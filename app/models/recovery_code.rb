# Código de recuperação do segundo fator: guardado como digest, gasto uma vez só.
class RecoveryCode < ApplicationRecord
  belongs_to :user

  HOW_MANY = 10
  # Sem 0/O/1/I/L: o usuário copia estes códigos à mão, e um caractere ambíguo vira
  # chamado de suporte no pior momento — quando ele perdeu o celular.
  ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze
  LENGTH = 10

  scope :unused, -> { where(used_at: nil) }

  def self.generate_for(user)
    transaction do
      user.recovery_codes.destroy_all
      HOW_MANY.times.map do
        code = LENGTH.times.map { ALPHABET.sample(random: SecureRandom) }.join
        user.recovery_codes.create!(code_digest: BCrypt::Password.create(code))
        code
      end
    end
  end

  def matches?(code)
    BCrypt::Password.new(code_digest) == code.to_s.strip.upcase
  rescue BCrypt::Errors::InvalidHash
    false
  end
end
