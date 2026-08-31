# Busca do header: encontra subcanais e estabelecimentos por qualquer identificador que
# apareça no cadastro, para chegar ao dado sem passar pela navegação.
class GlobalSearch
  MIN_LENGTH = 2
  LIMITS = { sub_channels: 5, establishments: 8 }.freeze

  attr_reader :query

  def initialize(query)
    @query = query.to_s.strip
  end

  def searchable?
    query.length >= MIN_LENGTH
  end

  def sub_channels
    @sub_channels ||= if searchable?
      SubChannel.includes(:channel).where("sub_channels.name ILIKE ?", like)
        .order(:name).limit(LIMITS[:sub_channels]).to_a
    else
      []
    end
  end

  def establishments
    @establishments ||= if searchable?
      Establishment.search(query).includes(:company, current_map_snapshot: :sub_channel)
        .order(:ec).limit(LIMITS[:establishments]).to_a
    else
      []
    end
  end

  def empty?
    searchable? && sub_channels.empty? && establishments.empty?
  end

  # Sem lote validado não há o que achar: a resposta certa é apontar a importação, não "nada".
  def base_empty?
    @base_empty = ImportBatch.validated.none? if @base_empty.nil?
    @base_empty
  end

  private

  def like
    "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
  end
end
