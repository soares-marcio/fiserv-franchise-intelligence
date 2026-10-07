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

    # Validade dos convidados (administrador não tem prazo): quantos têm data, quantos saem na
    # semana que vem e quantos já saíram — sem mexer em quem é quem.
    def with_validity_count = users.where.not(access_expires_on: nil).count
    def expiring_soon_count = users.where(access_expires_on: Date.current..7.days.from_now.to_date).count
    def expired_count = users.where(access_expires_on: ...Date.current).count

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

    # O histórico da trilha só existe desde a autenticação (09/2026): meses antes saem zerados.
    USAGE_MONTHS = 6
    RECENT = 30.days
    # O mês de Brasília, não o de UTC: created_at é guardado em UTC, sem fuso.
    LOCAL_MONTH = Arel.sql("date_trunc('month', (created_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Sao_Paulo')")

    # Uma linha por mês, do mais recente ao mais antigo: quem entrou, quantas entradas,
    # exportações e arquivos importados. É a base da cobrança por usuário ativo.
    def monthly_usage
      months = (0...USAGE_MONTHS).map { |back| Date.current.beginning_of_month.prev_month(back) }
      since = months.last.in_time_zone
      logins = org_events.where(action: "session.start", created_at: since..)
      columns = {
        people: logins.group(LOCAL_MONTH).distinct.count(:user_id),
        logins: logins.group(LOCAL_MONTH).count,
        exports: org_events.where(action: "report.export", created_at: since..).group(LOCAL_MONTH).count,
        files: validated_batches.where(created_at: since..).group(LOCAL_MONTH).count
      }.transform_values { |counts| counts.transform_keys(&:to_date) }
      months.map { |month| { month:, **columns.transform_values { |counts| counts.fetch(month, 0) } } }
    end

    # Contagens dos últimos 30 dias. O reinício do segundo fator feito pela plataforma é
    # evento dela (sem organização) e entra pela conta afetada.
    def security
      recent = org_events.where(created_at: RECENT.ago..)
      { refused: recent.where(action: "session.failed").count,
        lockouts: recent.where(action: "session.failed").where("metadata->>'bloqueada' = 'true'").count,
        wrong_codes: recent.where(action: "mfa.failed").count,
        mfa_resets: events_about_users("user.mfa_reset").where(created_at: RECENT.ago..).count,
        expired_access: recent.where(action: "session.expired_access").count,
        locked_now: users.where("locked_until > ?", Time.current).count }
    end

    def portfolio_health
      last = validated_batches.maximum(:created_at)
      { days_since_file: last && (Date.current - last.to_date).to_i,
        failed_recently: batches.where(status: "failed", created_at: RECENT.ago..).count,
        in_review: batches.where(status: "pending_review").count,
        processing: batches.where(status: "pending").count }
    end

    # Quem apaga é a organização (evento dela, com o Master); quem restaura é a plataforma
    # (evento sem organização, registrado sobre a organização). O REPORT_ID vem do metadado
    # ou do Master do evento — nunca o nome.
    DELETION_ACTIONS = %w[channel.deleted channel.restored sub_channel.deleted sub_channel.restored].freeze

    def deletion_history
      AuditEvent.where(action: DELETION_ACTIONS)
        .where("organization_id = :id OR (organization_id IS NULL AND record_type = 'Organization' AND record_id = :id)",
          id: @organization.id)
        .includes(:user, :channel).order(created_at: :desc).limit(20)
    end

    def self.report_id_of(event) = event.metadata["report_id"].presence || event.channel&.external_id

    ACCESS_ACTIONS = { invites: "user.created", permission_changes: "user.access_changed",
      validity_changes: "user.access_validity_changed", deactivations: "user.deactivated" }.freeze

    # Em números: quantas mudanças e quantas contas tocadas, sem dizer quais telas.
    def access_management
      recent = events_about_users(ACCESS_ACTIONS.values).where(created_at: RECENT.ago..)
      ACCESS_ACTIONS.transform_values { |action| recent.where(action:).count }
        .merge(accounts: recent.distinct.count(:record_id))
    end

    private

    def org_events = AuditEvent.where(organization_id: @organization.id)
    def batches = @organization.import_batches.active

    # Eventos sobre as contas da organização, venham dela ou da plataforma.
    def events_about_users(actions)
      AuditEvent.where(action: actions, record_type: "User", record_id: users.select(:id))
    end

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
