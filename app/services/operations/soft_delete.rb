module Operations
  # Apagar e restaurar Master e MIC. Apagar é marcar: os dados ficam, a carteira some de
  # toda tela pelo escopo de acesso, e só a plataforma restaura.
  #
  # O Master marca junto os ECs e os lotes dele, no mesmo instante: são eles que ocupam as
  # unicidades (EC e arquivo) que a planilha seguinte do mesmo REPORT_ID precisa usar para
  # nascer como Master novo. O mesmo instante é o que a restauração usa para devolver só o
  # que saiu com o Master.
  class SoftDelete
    BLOCKING_STATUSES = %w[pending pending_review].freeze

    def self.delete_channel(channel:, actor:, confirmation:)
      confirm!(confirmation, channel.name, "do Master")
      if channel.import_batches.active.where(status: BLOCKING_STATUSES).exists?
        raise ArgumentError, "Há arquivo deste Master em processamento ou em revisão. Termine ou " \
          "descarte o lote antes de apagar o Master."
      end

      now = Time.current
      counts = channel_counts(channel)
      holders = grant_holders(channel_id: channel.id)
      ApplicationRecord.transaction do
        channel.update!(deleted_at: now, deleted_by: actor)
        channel.establishments.active.update_all(deleted_at: now)
        channel.import_batches.active.update_all(deleted_at: now)
      end
      revoke_sessions(holders)
      counts
    end

    # Tudo ou nada, e recusado quando o REPORT_ID, um EC ou um arquivo já foram ocupados por
    # um Master novo: restaurar não pode criar duas carteiras disputando o mesmo EC.
    def self.restore_channel(channel:)
      raise ArgumentError, "Este Master não está apagado." unless channel.deleted?

      restore_conflicts!(channel)
      stamp = channel.deleted_at
      ApplicationRecord.transaction do
        channel.establishments.where(deleted_at: stamp).update_all(deleted_at: nil)
        channel.import_batches.where(deleted_at: stamp).update_all(deleted_at: nil)
        channel.update!(deleted_at: nil, deleted_by: nil)
      end
      revoke_sessions(grant_holders(channel_id: channel.id))
      channel
    end

    def self.delete_sub_channel(sub_channel:, actor:, confirmation:)
      confirm!(confirmation, sub_channel.name, "do MIC")
      holders = grant_holders(channel_id: sub_channel.channel_id)
      sub_channel.update!(deleted_at: Time.current, deleted_by: actor)
      revoke_sessions(holders)
      { "ecs" => current_establishments(sub_channel).count }
    end

    def self.restore_sub_channel(sub_channel:)
      raise ArgumentError, "Este MIC não está apagado." unless sub_channel.deleted?
      if SubChannel.active.exists?(channel_id: sub_channel.channel_id, name: sub_channel.name)
        raise ArgumentError, "Uma planilha nova já trouxe um MIC com este nome no mesmo Master. " \
          "Restaurar criaria dois MICs iguais."
      end

      sub_channel.update!(deleted_at: nil, deleted_by: nil)
      revoke_sessions(grant_holders(channel_id: sub_channel.channel_id))
      sub_channel
    end

    # Os números que a tela de confirmação mostra e a trilha guarda. Nada de CNPJ.
    def self.channel_counts(channel)
      { "lotes" => channel.import_batches.active.count, "ecs" => channel.establishments.active.count,
        "mics" => channel.sub_channels.active.count,
        "acessos" => AccessGrant.where(channel_id: channel.id).distinct.count(:user_id) }
    end

    # Os ECs cujo último vínculo é este MIC: é o que some da tela junto com ele.
    def self.current_establishments(sub_channel)
      Establishment.active.joins(:current_map_snapshot).where(map_snapshots: { sub_channel_id: sub_channel.id })
    end

    def self.confirm!(confirmation, name, what)
      return if confirmation.to_s.strip == name

      raise ArgumentError, "Digite o nome #{what} exatamente como aparece para confirmar."
    end

    def self.restore_conflicts!(channel)
      if Channel.active.exists?(external_id: channel.external_id)
        raise ArgumentError, "O REPORT_ID #{channel.external_id} já tem um Master ativo, criado por uma " \
          "planilha nova. Restaurar criaria duas carteiras com o mesmo REPORT_ID."
      end
      ecs = channel.establishments.where(deleted_at: channel.deleted_at).select(:ec)
      if Establishment.active.where(ec: ecs).exists?
        raise ArgumentError, "Há ECs deste Master já ativos em outro Master. Restaurar os duplicaria."
      end
      checksums = channel.import_batches.where(deleted_at: channel.deleted_at).select(:file_checksum)
      return unless ImportBatch.active.where(file_checksum: checksums).exists?

      raise ArgumentError, "Um arquivo deste Master já foi importado de novo. Restaurar duplicaria o lote."
    end

    # Toda mudança de escopo derruba as sessões abertas de quem é afetado — mesma regra da
    # mudança de permissão.
    def self.grant_holders(channel_id:)
      AccessGrant.where(channel_id:).distinct.pluck(:user_id)
    end

    def self.revoke_sessions(user_ids)
      Session.where(user_id: user_ids).destroy_all
    end

    private_class_method :confirm!, :restore_conflicts!, :grant_holders, :revoke_sessions
  end
end
