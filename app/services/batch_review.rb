# O que muda na carteira se este lote for aprovado.
#
# Existe porque o portal enxerga **um único lote por Master** — o de maior id entre os
# validados (AuditViews.latest_batches_sql). Um arquivo parcial, então, não "acrescenta"
# nada: ele vira a foto oficial do Master, e todo EC que não estiver nele desaparece dos
# relatórios. Esse buraco é anterior à autenticação; o que muda agora é que alguém olha
# antes.
#
# A comparação é entre o lote pendente e o lote vigente do mesmo canal, os dois já com
# snapshots gravados — por isso não há estrutura nova aqui, só leitura.
class BatchReview
  def initialize(batch)
    @batch = batch
  end

  attr_reader :batch

  def current_batch_id
    return @current_batch_id if defined?(@current_batch_id)

    @current_batch_id = ImportBatch.validated.where(channel_id: batch.channel_id)
      .where.not(id: batch.id)
      .where(MapSnapshot.where("map_snapshots.import_batch_id = import_batches.id").arel.exists)
      .maximum(:id)
  end

  # A lista que justifica a quarentena: ECs que a carteira tem hoje e o arquivo não traz.
  # Aprovar faz cada um deles sumir das telas.
  def leaving
    @leaving ||= snapshot_rows(current_batch_id).reject { |ec, _| incoming_by_ec.key?(ec) }
  end

  def entering
    @entering ||= incoming.reject { |ec, _| current_by_ec.key?(ec) }
  end

  # EC que continua na carteira, mas passa a pertencer a outro MIC. Não é erro — acontece
  # de verdade —, mas muda de dono quem lê e quem recebe a remuneração, então é decisão.
  def moving
    @moving ||= incoming.filter_map do |ec, linha|
      anterior = current_by_ec[ec]
      next if anterior.nil? || anterior[:sub_channel] == linha[:sub_channel]

      [ ec, { from: anterior[:sub_channel], to: linha[:sub_channel], cnpj: linha[:cnpj] } ]
    end.to_h
  end

  # CNPJ com ECs em mais de um MIC dentro do próprio arquivo: anomalia conhecida do domínio,
  # e a tela de revisão é o lugar de mostrá-la antes, não depois.
  def split_cnpjs
    @split_cnpjs ||= incoming.values.group_by { |linha| linha[:cnpj] }
      .select { |_cnpj, linhas| linhas.map { |l| l[:sub_channel] }.uniq.size > 1 }
      .transform_values { |linhas| linhas.map { |l| l[:sub_channel] }.uniq.sort }
  end

  def incoming_count = incoming.size
  def current_count = current_by_ec.size

  def incoming_revenue = revenue_of(batch.id)
  def current_revenue = current_batch_id ? revenue_of(current_batch_id) : nil

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
  def comparable_periods?
    return false if current_batch&.current_period.blank?
    return false unless batch.current_period == current_batch.current_period

    corte_novo = batch.current_month_cutoff_day
    corte_atual = current_batch.current_month_cutoff_day
    corte_novo.present? && corte_atual.present? && corte_novo >= corte_atual
  end

  def current_batch
    @current_batch ||= current_batch_id && ImportBatch.find_by(id: current_batch_id)
  end

  # Primeiro envio de um Master não tem com o que comparar: não há carteira a perder.
  def first_of_channel? = current_batch_id.nil?

  def removes_establishments? = leaving.any?

  # Motivos pelos quais este lote precisa de revisão. Vazio significa que pode consolidar
  # direto, como sempre foi.
  def review_reasons(uploader:)
    motivos = []
    motivos << :no_approval_permission unless uploader.nil? || uploader.permitted?(Permission::BATCHES_APPROVE)
    motivos << :removes_establishments if removes_establishments?
    motivos << :moves_sub_channels if moving.any?
    motivos << :revenue_drop if revenue_change && revenue_change <= -REVENUE_DROP_LIMIT
    motivos
  end

  # Queda de 40% no faturamento total do Master entre dois arquivos seguidos não é oscilação
  # de carteira: é arquivo incompleto ou competência trocada.
  REVENUE_DROP_LIMIT = 40

  private

  def incoming = incoming_by_ec

  def incoming_by_ec
    @incoming_by_ec ||= snapshot_rows(batch.id)
  end

  def current_by_ec
    @current_by_ec ||= current_batch_id ? snapshot_rows(current_batch_id) : {}
  end

  # Uma consulta por lote, com o MIC junto: a tela mostra EC, CNPJ e MIC de cada linha.
  def snapshot_rows(import_batch_id)
    return {} if import_batch_id.nil?

    MapSnapshot.where(import_batch_id:)
      .joins(:establishment, :sub_channel)
      .joins("JOIN companies ON companies.id = establishments.company_id")
      .pluck("establishments.ec", "companies.cnpj", "sub_channels.name")
      .to_h { |ec, cnpj, sub_channel| [ ec, { cnpj:, sub_channel: } ] }
  end

  def revenue_of(import_batch_id)
    RevenueSnapshot.where(import_batch_id:).sum(:current_month_total) || 0
  end
end
