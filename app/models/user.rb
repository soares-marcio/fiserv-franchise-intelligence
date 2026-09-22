class User < ApplicationRecord
  include PublicIdentifier

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :recovery_codes, dependent: :destroy
  has_many :access_grants, dependent: :destroy
  has_many :batch_grants, dependent: :destroy
  belongs_to :created_by, class_name: "User", optional: true

  # O segredo do TOTP é o único dado do portal cifrado em repouso: com ele, quem alcança o
  # banco gera códigos válidos e passa pelo segundo fator.
  encrypts :otp_secret

  normalizes :email_address, with: ->(e) { e.to_s.strip.downcase }

  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP, message: "não parece um endereço válido" }
  validates :name, presence: true
  # 12 caracteres porque o portal passa a ser alcançável pela internet, sem o Cloudflare
  # Access na frente: a senha deixa de ser a segunda barreira e vira a primeira.
  validates :password, length: { minimum: 12 }, allow_nil: true
  validate :permissions_must_be_known

  scope :active, -> { where(deactivated_at: nil) }

  def active? = deactivated_at.nil?
  def locked? = locked_until.present? && locked_until.future?
  def mfa_enabled? = mfa_enabled_at.present?

  # Super admin não recebe chave a chave: pode tudo, por definição. Guardar a lista inteira
  # nele criaria dois lugares para acrescentar permissão nova.
  def permitted?(key)
    super_admin? || permissions.include?(key)
  end

  def unused_recovery_codes = recovery_codes.where(used_at: nil)

  private

  def permissions_must_be_known
    desconhecidas = permissions - Permission::KEYS
    return if desconhecidas.empty?

    errors.add(:permissions, "desconhecidas: #{desconhecidas.join(', ')}")
  end
end
