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
  # Mínimo de 8 por decisão de 30/09/2026 (o padrão era 12); a troca obrigatória no primeiro
  # acesso e o segundo fator continuam obrigatórios.
  validates :password, length: { minimum: 8 }, allow_nil: true
  validate :permissions_must_be_known
  validate :permissions_must_be_coherent
  # Rebaixar ou desativar o último administrador da plataforma ativo deixaria o portal sem
  # quem crie organizações — inclusive sem quem possa nomear outro.
  validate :keep_one_active_platform_admin, on: :update
  validate :access_expiry_must_make_sense
  validate :access_expiry_within_grantor_limit

  # Prazo de quem concede, quando há: o delegado com acesso até uma data não dá a outra
  # pessoa acesso além dela, nem indeterminado. Preenchido só pelo Operations::SaveUser.
  attr_accessor :access_validity_limit

  # Dez tentativas erradas (senha ou código) bloqueiam a conta por quinze minutos. O
  # contador fica no banco, e não no cache, porque o cache do ambiente de teste é
  # :null_store — um bloqueio que não se consegue testar não existe.
  MAX_FAILED_ATTEMPTS = 10
  LOCK_PERIOD = 15.minutes

  scope :active, -> { where(deactivated_at: nil) }

  def active? = deactivated_at.nil?
  # O que decide se a pessoa entra: conta ativa e organização não suspensa. `active?` continua
  # sendo só da conta — é o que as telas de suporte mostram e revertem.
  def sign_in_allowed? = active? && !organization&.suspended? && !access_expired?
  # Vale até o fim do dia escolhido, no horário de Brasília (config.time_zone).
  def access_expired? = access_expires_on.present? && Date.current > access_expires_on

  def access_days_left
    (access_expires_on - Date.current).to_i if access_expires_on
  end
  def locked? = locked_until.present? && locked_until.future?
  def mfa_enabled? = mfa_enabled_at.present?

  # A conta da plataforma não tem chave nenhuma: ela cria organizações e não vê dado. O
  # administrador da organização tem todas, por definição — guardar a lista inteira nele
  # criaria dois lugares para acrescentar permissão nova.
  def permitted?(key)
    return false if platform_admin?

    organization_admin? || permissions.include?(key)
  end

  def unused_recovery_codes = recovery_codes.where(used_at: nil)

  # Toda mudança de senha, permissão ou escopo derruba as sessões abertas: sem isso, quem
  # perdeu acesso continuaria dentro até a sessão expirar sozinha.
  def revoke_sessions!
    sessions.destroy_all
  end

  # As três ações de suporte, usadas pela organização sobre os seus e pela plataforma sobre
  # os administradores. Nenhuma audita: quem audita é quem chama, com a requisição em mãos.
  def reset_mfa!
    transaction do
      update!(otp_secret: nil, mfa_enabled_at: nil, otp_last_used_at: nil)
      recovery_codes.destroy_all
      revoke_sessions!
    end
  end

  def deactivate!
    transaction do
      update!(deactivated_at: Time.current)
      revoke_sessions!
    end
  end

  def reactivate!
    update!(deactivated_at: nil)
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
    loses_role = platform_admin_was && (!platform_admin? || deactivated_at.present?)
    return unless loses_role
    return if User.active.where(platform_admin: true).where.not(id: id).exists?

    errors.add(:base, "precisa sobrar ao menos um administrador da plataforma ativo")
  end

  # Data passada ou de hoje não é prazo, é desativação. Administrador não tem prazo: a
  # organização ficaria sem quem administra, e quem o cria é a plataforma.
  def access_expiry_must_make_sense
    return if access_expires_on.nil?

    if platform_admin? || organization_admin?
      errors.add(:access_expires_on, "não se aplica a administrador")
    elsif will_save_change_to_access_expires_on? && access_expires_on <= Date.current
      errors.add(:access_expires_on, "precisa ser depois de hoje")
    end
  end

  def access_expiry_within_grantor_limit
    return if access_validity_limit.nil?
    return if access_expires_on.present? && access_expires_on <= access_validity_limit

    errors.add(:access_expires_on, "não pode passar de " \
      "#{I18n.l(access_validity_limit, format: '%d/%m/%Y')}, a validade do seu próprio acesso")
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

  # Chave sem a base não abre tela nenhuma: recusar no convite é melhor do que a pessoa
  # descobrir entrando.
  def permissions_must_be_coherent
    Permission.missing_requirements(permissions).each do |key, _bases|
      errors.add(:permissions, %("#{Permission.label(key)}" #{Permission.requirement_text(key)}))
    end
  end

  def permissions_must_be_known
    unknown = permissions - Permission::KEYS
    return if unknown.empty?

    errors.add(:permissions, "desconhecidas: #{unknown.join(', ')}")
  end
end
