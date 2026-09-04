class Establishment < ApplicationRecord
  include PublicIdentifier

  belongs_to :company
  belongs_to :channel
  belongs_to :primary_establishment, class_name: "Establishment", optional: true
  has_many :duplicate_establishments, class_name: "Establishment", foreign_key: :primary_establishment_id,
    dependent: :restrict_with_exception
  has_many :map_snapshots, dependent: :restrict_with_exception
  # Só o snapshot mais recente, decidido no banco: a condição vale tanto para o JOIN da busca
  # quanto para o preload. Com order/LIMIT o JOIN abria uma linha por planilha importada e o
  # preload carregava o histórico inteiro de cada EC para descartar tudo menos o último.
  has_one :current_map_snapshot, -> {
    where("NOT EXISTS (SELECT 1 FROM map_snapshots newer " \
      "WHERE newer.establishment_id = map_snapshots.establishment_id AND newer.id > map_snapshots.id)")
  }, class_name: "MapSnapshot"
  has_many :revenue_snapshots, dependent: :restrict_with_exception

  validates :ec, format: { with: /\A\d{8}\z/ }, uniqueness: true

  # Busca livre pelo que aparece no cadastro: EC, CNPJ, nomes, cidade, CNAE ou subcanal.
  # CNPJ e EC ficam só com dígitos no banco; o termo limpo cobre a colagem formatada.
  scope :search, ->(query) {
    like = "%#{sanitize_sql_like(query.to_s.strip)}%"
    digits = SearchNormalizer.digits(query)
    clauses = "establishments.ec ILIKE :q OR companies.cnpj ILIKE :q OR " \
      "map_snapshots.trade_name ILIKE :q OR map_snapshots.legal_name ILIKE :q OR " \
      "map_snapshots.city ILIKE :q OR map_snapshots.cnae_code ILIKE :q OR " \
      "map_snapshots.cnae_description ILIKE :q OR sub_channels.name ILIKE :q"
    binds = { q: like }
    if digits
      clauses += " OR companies.cnpj ILIKE :digits OR establishments.ec ILIKE :digits"
      binds[:digits] = "%#{sanitize_sql_like(digits)}%"
    end
    left_joins(:company, current_map_snapshot: :sub_channel).where(clauses, binds)
  }
  validate :primary_is_from_same_company

  private

  def primary_is_from_same_company
    return if primary_establishment.blank? || primary_establishment.company_id == company_id

    errors.add(:primary_establishment, "deve pertencer ao mesmo CNPJ")
  end
end
