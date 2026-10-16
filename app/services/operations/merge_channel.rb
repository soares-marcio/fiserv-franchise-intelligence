module Operations
  # Junta um Master em outro, com os MICs dele virando MICs do destino. Existe porque um
  # nível da hierarquia da Fiserv foi lido como Master: a Região Goiás (REPORT_ID 719) era um
  # MIC de Ramos e Silva (1478), e em 13/10/2026 a Fiserv passou a mandá-lo sob o 1478 —
  # o import recusou, com razão, os 394 ECs "de outro canal".
  #
  # Não é tela nem migração: roda por console, a pedido, porque migração roda sozinha no
  # deploy e nada no berry muda por conta própria. É tudo ou nada, numa transação, e mexe na
  # ordem que as FKs exigem — nenhuma é DEFERRABLE, e as compostas conferem o par
  # (sub_channel_id, channel_id) a cada UPDATE.
  #
  # O que muda de dono: ECs, lotes, fotos, propostas, faturamento (cru e consolidado),
  # volumes, cobertura, anomalias e concessões. A trilha antiga continua apontando para a
  # origem, que fica apagada (marcada) — é registro do que aconteceu, não carteira.
  class MergeChannel
    BLOCKING_STATUSES = SoftDelete::BLOCKING_STATUSES

    # Tabelas com o par (channel_id, sub_channel_id) e FK composta para sub_channels.
    SUB_CHANNEL_TABLES = %w[map_snapshots revenue_snapshots activation_proposals].freeze
    # Tabelas só com channel_id. daily_revenues é particionada: o UPDATE no pai alcança as
    # partições. O consolidado precisa ir junto — as views juntam
    # revenue.channel_id = snapshot.channel_id, e o faturamento sumiria calado.
    CHANNEL_TABLES = %w[
      establishments import_batches daily_revenues daily_revenues_consolidated
      monthly_volumes monthly_volumes_consolidated
    ].freeze

    def self.call(source:, target:, actor:)
      new(source:, target:, actor:).call
    end

    def initialize(source:, target:, actor:)
      @source = source
      @target = target
      @actor = actor
    end

    def call
      refuse_unless_mergeable!
      holders = AccessGrant.where(channel_id: [ @source.id, @target.id ]).distinct.pluck(:user_id)
      counts = { "ecs" => @source.establishments.active.count, "lotes" => @source.import_batches.active.count }
      mapping = nil
      ApplicationRecord.transaction do
        mapping = map_sub_channels
        move_sub_channel_tables(mapping)
        move_channel_tables
        merge_coverages
        merge_anomalies
        merge_grants(mapping)
        retire_source(mapping)
        Audit.record("channel.merged", user: @actor, record: @target, channel: @target,
          metadata: counts.merge("origem" => @source.name, "mics" => mapping.keys.map(&:name).sort))
      end
      Session.where(user_id: holders).destroy_all
      AuditViews.refresh!
      counts
    end

    private

    def refuse_unless_mergeable!
      raise ArgumentError, "Origem e destino são o mesmo Master." if @source.id == @target.id
      raise ArgumentError, "Os dois Masters precisam ser da mesma organização." if @source.organization_id != @target.organization_id
      raise ArgumentError, "Um dos Masters está apagado." if @source.deleted? || @target.deleted?
      if ImportBatch.active.where(channel_id: [ @source.id, @target.id ], status: BLOCKING_STATUSES).exists?
        raise ArgumentError, "Há arquivo de um dos Masters em processamento ou em revisão. Termine ou " \
          "descarte o lote antes de juntar."
      end
      # O MIC apagado da origem não teria para onde ir sem ser ressuscitado no destino.
      if @source.sub_channels.where.not(deleted_at: nil).exists?
        raise ArgumentError, "A origem tem MIC apagado. Restaure-o ou deixe-o como está antes de juntar."
      end
      names = @source.sub_channels.active.pluck(:name)
      deleted = @target.sub_channels.where(name: names).where.not(deleted_at: nil).pluck(:name)
      active = @target.sub_channels.active.where(name: names).pluck(:name)
      return if (deleted - active).empty?

      raise ArgumentError, "O destino tem MIC apagado com o mesmo nome: #{(deleted - active).sort.to_sentence}. " \
        "Restaure-o antes de juntar, para os dados não caírem num MIC apagado."
    end

    # MIC da origem → MIC do destino, pelo nome: é o nome que a planilha traz, e o arquivo
    # seguinte do destino vai achá-lo por ele (BinImport::Importer#find_sub_channel).
    def map_sub_channels
      @source.sub_channels.active.to_h do |sub_channel|
        [ sub_channel, @target.sub_channels.active.find_or_create_by!(name: sub_channel.name) ]
      end
    end

    def move_sub_channel_tables(mapping)
      mapping.each do |from, to|
        SUB_CHANNEL_TABLES.each do |table|
          execute("UPDATE #{table} SET channel_id = $1, sub_channel_id = $2 WHERE sub_channel_id = $3",
            @target.id, to.id, from.id)
        end
      end
    end

    def move_channel_tables
      CHANNEL_TABLES.each do |table|
        execute("UPDATE #{table} SET channel_id = $1 WHERE channel_id = $2", @target.id, @source.id)
      end
    end

    # A cobertura do destino fica com o maior dia conhecido entre os dois; a linha da origem
    # colidiria com o índice único (channel_id, period).
    def merge_coverages
      execute(<<~SQL, @target.id, @source.id)
        INSERT INTO period_coverages (channel_id, period, max_known_day, closed, last_import_batch_id,
          created_at, updated_at)
        SELECT $1, period, max_known_day, closed, last_import_batch_id, created_at, NOW()
        FROM period_coverages WHERE channel_id = $2
        ON CONFLICT (channel_id, period) DO UPDATE SET
          max_known_day = GREATEST(period_coverages.max_known_day, EXCLUDED.max_known_day),
          closed = period_coverages.closed OR EXCLUDED.closed,
          updated_at = NOW()
      SQL
      execute("DELETE FROM period_coverages WHERE channel_id = $1", @source.id)
    end

    # Anomalia é marca deduplicada por (canal, tipo, empresa, EC): a da origem que já existe
    # no destino é a mesma anomalia e sai; as outras mudam de dono.
    def merge_anomalies
      execute(<<~SQL, @target.id, @source.id)
        UPDATE data_anomalies source SET channel_id = $1
        WHERE source.channel_id = $2 AND NOT EXISTS (
          SELECT 1 FROM data_anomalies target
          WHERE target.channel_id = $1 AND target.anomaly_type = source.anomaly_type
            AND target.company_id IS NOT DISTINCT FROM source.company_id
            AND target.establishment_id IS NOT DISTINCT FROM source.establishment_id
        )
      SQL
      execute("DELETE FROM data_anomalies WHERE channel_id = $1", @source.id)
    end

    # Quem tinha a origem inteira passa a ter os MICs dela no destino; quem tinha um MIC da
    # origem, o MIC equivalente. Quem já tem o destino inteiro não precisa de nada.
    def merge_grants(mapping)
      whole_target = AccessGrant.where(channel_id: @target.id, sub_channel_id: nil).pluck(:user_id).to_set
      AccessGrant.where(channel_id: @source.id).find_each do |grant|
        next if whole_target.include?(grant.user_id)

        sub_channels = grant.sub_channel_id ? [ mapping.fetch(grant.sub_channel) ] : mapping.values
        sub_channels.each do |sub_channel|
          AccessGrant.find_or_create_by!(user_id: grant.user_id, channel: @target, sub_channel:) do |created|
            created.created_by = @actor
          end
        end
      end
      AccessGrant.where(channel_id: @source.id).delete_all
    end

    def retire_source(mapping)
      now = Time.current
      SubChannel.where(id: mapping.keys.map(&:id)).update_all(deleted_at: now, deleted_by_id: @actor&.id)
      @source.update!(deleted_at: now, deleted_by: @actor)
    end

    def execute(sql, *binds)
      ApplicationRecord.connection.exec_query(sql, "MergeChannel", binds)
    end
  end
end
