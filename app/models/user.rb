class User < ApplicationRecord
  include PublicIdentifier

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :recovery_codes, dependent: :destroy
  has_many :access_grants, dependent: :destroy
  has_many :batch_grants, dependent: :destroy
  belongs_to :created_by, class_name: "User", optional: true
  # A conta da plataforma não pertence a organização nenhuma; toda outra pertence a uma.
  # O banco tem o mesmo CHECK (users_platform_or_organization); aqui a mensagem é legível.
  belongs_to :organization, optional: true
  validate :platform_or_organization

  # O segredo do TOTP é o único dado do portal cifrado em repouso: com ele, quem alcança o
  # banco gera códigos válidos e passa pelo segundo fator.
  encrypts :otp_secret
  # A senha provisória do convite, para quem convidou entregar pessoalmente: fica visível na
  # listagem até a pessoa trocá-la — e some no instante da troca, abaixo.
  encrypts :provisional_password

  normalizes :email_address, with: ->(e) { e.to_s.strip.downcase }

  before_save :forget_provisional_password, if: -> { persisted? && will_save_change_to_password_digest? }

  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP, message: "não parece um endereço válido" }
  validates :name, presence: true
  # 12 caracteres porque o portal passa a ser alcançável pela internet, sem o Cloudflare
  # Access na frente: a senha deixa de ser a segunda barreira e vira a primeira.
  validates :password, length: { minimum: 12 }, allow_nil: true
  validate :permissions_must_be_known
  # Rebaixar ou desativar o último administrador geral ativo deixaria o portal sem ninguém
  # que possa tudo — inclusive sem quem possa nomear outro.
  validate :keep_one_active_platform_admin, on: :update

  # Dez tentativas erradas (senha ou código) bloqueiam a conta por quinze minutos. O
  # contador fica no banco, e não no cache, porque o cache do ambiente de teste é
  # :null_store — um bloqueio que não se consegue testar não existe.
  MAX_FAILED_ATTEMPTS = 10
  LOCK_PERIOD = 15.minutes

  scope :active, -> { where(deactivated_at: nil) }

  def active? = deactivated_at.nil?
  def locked? = locked_until.present? && locked_until.future?
  def mfa_enabled? = mfa_enabled_at.present?

  # Quem administra — a plataforma ou a própria organização — não recebe chave a chave: pode
  # tudo, por definição. Guardar a lista inteira criaria dois lugares para acrescentar
  # permissão nova.
  def permitted?(key)
    platform_admin? || organization_admin? || permissions.include?(key)
  end

  def unused_recovery_codes = recovery_codes.where(used_at: nil)

  # Toda mudança de senha, permissão ou escopo derruba as sessões abertas: sem isso, quem
  # perdeu acesso continuaria dentro até a sessão expirar sozinha.
  def revoke_sessions!
    sessions.destroy_all
  end

  def register_failed_attempt!
    increment!(:failed_attempts)
    return unless failed_attempts >= MAX_FAILED_ATTEMPTS

    update!(locked_until: LOCK_PERIOD.from_now, failed_attempts: 0)
  end

  def register_successful_attempt!
    update!(failed_attempts: 0, locked_until: nil)
  end

  # Trocou a senha: a provisória deixa de existir — inclusive para quem convidou.
  def forget_provisional_password
    self.provisional_password = nil
  end

  def keep_one_active_platform_admin
    perde = platform_admin_was && (!platform_admin? || deactivated_at.present?)
    return unless perde
    return if User.active.where(platform_admin: true).where.not(id: id).exists?

    errors.add(:base, "precisa sobrar ao menos um administrador geral ativo")
  end

  private

  def platform_or_organization
    if platform_admin?
      errors.add(:organization, "a conta da plataforma não pertence a organização nenhuma") if organization_id.present?
      errors.add(:organization_admin, "a conta da plataforma não administra organização") if organization_admin?
    elsif organization_id.nil?
      errors.add(:organization, "é obrigatória para quem não é da plataforma")
    end
  end

  def permissions_must_be_known
    desconhecidas = permissions - Permission::KEYS
    return if desconhecidas.empty?

    errors.add(:permissions, "desconhecidas: #{desconhecidas.join(', ')}")
  end
end
