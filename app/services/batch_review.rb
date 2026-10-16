# O que muda na carteira se este lote for aprovado.
#
# A carteira vigente é escolhida por MIC (AuditViews.current_snapshots_sql): a Fiserv manda
# a carteira de um Master em mais de um arquivo, e cada arquivo vale para os MICs que traz.
# A comparação, então, é entre o lote pendente e a carteira vigente **dos MICs dele** — os
# outros MICs do Master não são tocados por este arquivo e continuam com o arquivo deles.
# Um arquivo que traz um MIC pela metade continua parando aqui: o EC que ele não traz sai.
#
# Os snapshots do lote pendente já estão gravados — por isso não há estrutura nova aqui, só
# leitura.
class BatchReview
  def initialize(batch)
    @batch = batch
  end

  attr_reader :batch

  # A lista que justifica a quarentena: ECs que a carteira tem hoje e o arquivo não traz.
  # Aprovar faz cada um deles sumir das telas.
  def leaving
    @leaving ||= current_of_batch_sub_channels.reject { |ec, _| incoming_by_ec.key?(ec) }
  end

  def entering
    @entering ||= incoming.reject { |ec, _| current_by_ec.key?(ec) }
  end

  # EC que continua na carteira, mas passa a pertencer a outro MIC. Não é erro — acontece
  # de verdade —, mas muda de dono quem lê e quem recebe a remuneração, então é decisão.
  def moving
    @moving ||= incoming.filter_map do |ec, row|
      previous = current_by_ec[ec]
      next if previous.nil? || previous[:sub_channel] == row[:sub_channel]

      [ ec, { from: previous[:sub_channel], to: row[:sub_channel], cnpj: row[:cnpj] } ]
    end.to_h
  end

  # CNPJ com ECs em mais de um MIC dentro do próprio arquivo: anomalia conhecida do domínio,
  # e a tela de revisão é o lugar de mostrá-la antes, não depois.
  def split_cnpjs
    @split_cnpjs ||= incoming.values.group_by { |row| row[:cnpj] }
      .select { |_cnpj, rows| rows.map { |l| l[:sub_channel] }.uniq.size > 1 }
      .transform_values { |rows| rows.map { |l| l[:sub_channel] }.uniq.sort }
  end

  def incoming_count = incoming.size
  def current_count = current_of_batch_sub_channels.size

  def incoming_revenue = revenue_of(batch.id)
  def current_revenue = first_of_channel? ? nil : current_revenue_of_batch_sub_channels

  # MICs do Master que este arquivo não traz, com a data do arquivo que segue valendo para
  # cada um. Não é motivo de revisão: é o Master chegando em mais de um arquivo.
  def untouched_sub_channels
    @untouched_sub_channels ||= current_by_ec.values
      .reject { |row| incoming_sub_channel_ids.include?(row[:sub_channel_id]) }
      .group_by { |row| row[:sub_channel] }
      .transform_values { |rows| rows.map { |row| row[:received_at] }.max }
      .sort.to_h
  end

  # Variação do faturamento total entre os dois lotes.
  #
  # Só compara dentro da **mesma competência**: entre meses diferentes a queda é esperada —
  # um arquivo do dia 5 do mês novo sempre traz menos que o mês anterior fechado, e tratar
  # isso como suspeita mandaria toda virada de mês para a fila de revisão.
  def revenue_change
    return nil unless comparable_periods?
    return nil if current_revenue.nil? || current_revenue.zero?

    ((incoming_revenue - current_revenue) / current_revenue * 100).round(1)
  end

  # Comparar faturamento só faz sentido entre arquivos da mesma competência **e** com
  # cobertura igual ou maior: dentro do mês o valor é acumulado dia a dia, então um arquivo
  # que cobre menos dias traz menos dinheiro por aritmética, não por perda de carteira —
  # e esse caso já tem detecção própria (a anomalia de cobertura menor, na consolidação).
  #
  # Com o Master em mais de um arquivo, a comparação é com os lotes vigentes dos MICs que este
  # arquivo traz, e todos eles precisam estar na mesma competência e não cobrir mais dias.
  def comparable_periods?
    batches = ImportBatch.where(id: current_of_batch_sub_channels.values.map { |row| row[:import_batch_id] }.uniq)
    return false if batches.empty? || batch.current_month_cutoff_day.blank?

    batches.all? do |current|
      current.current_period.present? && current.current_period == batch.current_period &&
        current.current_month_cutoff_day.present? &&
        batch.current_month_cutoff_day >= current.current_month_cutoff_day
    end
  end

  # Primeiro arquivo dos MICs que ele traz: não há carteira deles a perder.
  def first_of_channel? = current_of_batch_sub_channels.empty?

  def removes_establishments? = leaving.any?

  # Motivos pelos quais este lote precisa de revisão. Vazio significa que pode consolidar
  # direto, como sempre foi.
  def review_reasons(uploader:)
    reasons = []
    reasons << :no_approval_permission unless uploader.nil? || uploader.permitted?(Permission::BATCHES_APPROVE)
    reasons << :removes_establishments if removes_establishments?
    reasons << :moves_sub_channels if moving.any?
    reasons << :revenue_drop if revenue_change && revenue_change <= -REVENUE_DROP_LIMIT
    reasons
  end

  # Queda de 40% no faturamento dos MICs do arquivo entre dois arquivos seguidos não é
  # oscilação de carteira: é arquivo incompleto ou competência trocada.
  REVENUE_DROP_LIMIT = 40

  private

  def incoming = incoming_by_ec

  def incoming_by_ec
    @incoming_by_ec ||= snapshot_rows(MapSnapshot.where(import_batch_id: batch.id))
  end

  # A carteira vigente do Master inteiro, sem este lote: é contra ela que se sabe quem entra e
  # quem muda de MIC, mesmo que o MIC de origem esteja em outro arquivo.
  def current_by_ec
    @current_by_ec ||= snapshot_rows(current_map_snapshots)
  end

  # Só os MICs que o arquivo traz: é deles que o arquivo é a foto.
  def current_of_batch_sub_channels
    @current_of_batch_sub_channels ||= current_by_ec.select do |_ec, row|
      incoming_sub_channel_ids.include?(row[:sub_channel_id])
    end
  end

  def incoming_sub_channel_ids
    @incoming_sub_channel_ids ||= incoming.values.map { |row| row[:sub_channel_id] }.to_set
  end

  def current_map_snapshots
    MapSnapshot.where(id: current_snapshot_ids("map_snapshots"))
  end

  # A carteira vigente do Master como estaria sem este lote — o que vale hoje.
  def current_snapshot_ids(table)
    return [] if batch.channel_id.nil?

    AuditViews.current_snapshot_ids(table:, channel_id: batch.channel_id, except_batch_id: batch.id)
  end

  # Uma consulta por lote, com o MIC junto: a tela mostra EC, CNPJ e MIC de cada linha.
  def snapshot_rows(snapshots)
    snapshots.joins(:establishment, :sub_channel, :import_batch)
      .joins("JOIN companies ON companies.id = establishments.company_id")
      .pluck("establishments.ec", "companies.cnpj", "sub_channels.name", "sub_channels.id",
        "map_snapshots.import_batch_id", "import_batches.created_at")
      .to_h do |ec, cnpj, sub_channel, sub_channel_id, import_batch_id, received_at|
        [ ec, { cnpj:, sub_channel:, sub_channel_id:, import_batch_id:, received_at: } ]
      end
  end

  def revenue_of(import_batch_id)
    RevenueSnapshot.where(import_batch_id:).sum(:current_month_total) || 0
  end

  # O faturamento vigente dos MICs do arquivo, pela mesma regra da carteira.
  def current_revenue_of_batch_sub_channels
    RevenueSnapshot.where(id: current_snapshot_ids("revenue_snapshots"),
      sub_channel_id: incoming_sub_channel_ids.to_a).sum(:current_month_total) || 0
  end
end
