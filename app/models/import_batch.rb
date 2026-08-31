class ImportBatch < ApplicationRecord
  include PublicIdentifier

  # Dias sem receber arquivo a partir dos quais a carteira é considerada desatualizada.
  STALE_AFTER_DAYS = 12
  # Depois disso, um lote ainda pendente indica worker parado, não importação em curso.
  STUCK_AFTER = 5.minutes

  has_one_attached :source_file

  # Canal e template ficam nulos entre o upload e o fim do parse.
  belongs_to :channel, optional: true
  belongs_to :import_template, optional: true
  has_many :revenue_snapshots, dependent: :restrict_with_exception
  has_many :map_snapshots, dependent: :restrict_with_exception
  has_many :activation_proposals, dependent: :restrict_with_exception
  has_many :daily_revenues, dependent: :restrict_with_exception
  has_many :monthly_volumes, dependent: :restrict_with_exception

  validates :file_checksum, uniqueness: true

  scope :pending, -> { where(status: "pending") }
  scope :validated, -> { where(status: "validated") }

  # Atualiza a tela de importação sozinha quando o lote muda de status.
  broadcasts_refreshes_to ->(_batch) { "import_batches" }

  # Batimento do worker do Solid Queue; sem ele, todo upload fica pendente em silêncio.
  WORKER_HEARTBEAT_TIMEOUT = 2.minutes

  def self.worker_heartbeat_at
    SolidQueue::Process.where(kind: "Worker").maximum(:last_heartbeat_at)
  end

  def self.worker_alive?
    heartbeat = worker_heartbeat_at
    heartbeat.present? && heartbeat > WORKER_HEARTBEAT_TIMEOUT.ago
  end

  def self.last_received_at
    validated.maximum(:created_at)
  end

  def self.days_since_last_file
    received = last_received_at
    return unless received

    (Date.current - received.to_date).to_i
  end

  def self.stale?
    days = days_since_last_file
    days.nil? || days >= STALE_AFTER_DAYS
  end

  # Só um lote que falhou antes de gravar qualquer linha pode ser descartado; os demais
  # já alimentaram a consolidação e têm chaves apontando para eles.
  def discardable?
    status == "failed" && map_snapshots.none? && revenue_snapshots.none? &&
      activation_proposals.none? && daily_revenues.none?
  end

  def running?
    status == "pending" && created_at > STUCK_AFTER.ago
  end

  def stuck?
    status == "pending" && created_at <= STUCK_AFTER.ago
  end
end
