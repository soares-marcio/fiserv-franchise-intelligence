module Platform
  # A ficha de uma organização vista pela plataforma: contagens e datas, nunca conteúdo.
  # Nenhum nome de Master, CNPJ ou faturamento sai daqui — a plataforma administra contas,
  # não lê carteira.
  class OrganizationProfile
    def initialize(organization)
      @organization = organization
    end

    # Quem criou é quem registrou o evento; a organização migrada não tem esse evento e
    # devolve nada. A nomeação é registrada pelo administrador, com organização — por isso
    # a leitura é direta, e não pelo Scope da policy, que para a plataforma só devolve os
    # eventos de plataforma.
    def created_by = event("organization.created")&.user
    def named_at = event("organization.named")&.created_at

    def admins_count = users.where(organization_admin: true).count
    def members_count = users.where(organization_admin: false).count
    def active_count = users.active.count
    def first_access_pending_count = users.active.where(must_change_password: true).or(users.active.where(mfa_enabled_at: nil)).count

    def channels_count = @organization.channels.active.count
    def batches_count = validated_batches.count
    def last_file_on = validated_batches.maximum(:source_file_date)
    def notes_count = notes.count
    def attachments_count = attachments.count
    def attachments_bytes = attachments.joins(:blob).sum("active_storage_blobs.byte_size")

    # Os apagados, para a plataforma restaurar. Pelo REPORT_ID, e não pelo nome: a plataforma
    # administra contas, não lê carteira. O mesmo REPORT_ID pode aparecer mais de uma vez —
    # apagado, reimportado e apagado de novo —, e cada um é uma carteira distinta.
    def deleted_channels = @organization.channels.deleted.includes(:deleted_by).order(:external_id, :deleted_at)

    def deleted_sub_channels
      SubChannel.deleted.joins(:channel).merge(Channel.active).where(channels: { organization_id: @organization.id })
        .includes(:channel, :deleted_by).order(:deleted_at)
    end

    # Os números do que saiu junto com cada Master, contados pelo instante da marcação.
    def deleted_counts(channel)
      { batches: channel.import_batches.where(deleted_at: channel.deleted_at).count,
        establishments: channel.establishments.where(deleted_at: channel.deleted_at).count }
    end

    private

    def users = @organization.users
    def validated_batches = @organization.import_batches.active.validated
    def notes = CompanyNote.where(organization_id: @organization.id)

    def attachments
      texts = ActionText::RichText.where(record_type: "CompanyNote", record_id: notes.select(:id))
      ActiveStorage::Attachment.where(record_type: "ActionText::RichText", record_id: texts.select(:id))
    end

    def event(action)
      AuditEvent.where(record: @organization, action:).order(:created_at).first
    end
  end
end
