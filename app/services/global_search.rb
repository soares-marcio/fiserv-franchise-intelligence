# Busca do header: encontra subcanais e estabelecimentos por qualquer identificador que
# apareça no cadastro, para chegar ao dado sem passar pela navegação.
class GlobalSearch
  MIN_LENGTH = 2
  LIMITS = { sub_channels: 5, establishments: 8 }.freeze

  attr_reader :query

  # A busca é o caminho mais curto até um dado: sem recorte, digitar um CNPJ qualquer
  # revelaria em que Master ele está, e o nome do MIC junto.
  def initialize(query, access:)
    @query = query.to_s.strip
    @access = access
  end

  def searchable?
    query.length >= MIN_LENGTH
  end

  def sub_channels
    @sub_channels ||= if searchable?
      sub_channels_in_scope.includes(:channel).where("sub_channels.name ILIKE ?", like)
        .order(:name).limit(LIMITS[:sub_channels]).to_a
    else
      []
    end
  end

  def establishments
    @establishments ||= if searchable?
      Establishment.in_scope(@access).merge(Establishment.search(query))
        .includes(:company, current_map_snapshot: :sub_channel)
        .order(:ec).limit(LIMITS[:establishments]).to_a
    else
      []
    end
  end

  # CNPJs dos resultados que já têm anotação. Só a existência: a busca é um índice, não uma
  # leitura — o texto mora na ficha do cliente e no modal.
  def noted_cnpjs
    # Os ECs já vieram recortados, então os CNPJs também — a consulta aqui é sobre eles.
    @noted_cnpjs ||= CompanyNote.where(organization_id: @access.organization_id, cnpj: establishments.map { |e| e.company.cnpj }.uniq)
      .pluck(:cnpj).to_set
  end

  # Os MICs que o ator alcança: os do Master inteiro concedido, mais os avulsos.
  def sub_channels_in_scope
    SubChannel.where(channel_id: @access.full_channel_ids)
      .or(SubChannel.where(id: @access.sub_channel_ids))
  end

  def empty?
    searchable? && sub_channels.empty? && establishments.empty?
  end

  # Sem lote validado não há o que achar: a resposta certa é apontar a importação, não "nada".
  def base_empty?
    @base_empty = ImportBatch.validated.where(organization_id: @access.organization_id).none? if @base_empty.nil?
    @base_empty
  end

  private

  def like
    "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
  end
end
