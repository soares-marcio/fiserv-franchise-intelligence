module Operations
  # Criar e editar usuário, com as regras que impedem escalonamento de privilégio.
  #
  # Ficam aqui, e não só na policy, porque a policy protege a tela: console, seed e job
  # passariam por fora. E ficam num lugar só para as duas checagens — permissões e escopo —
  # não divergirem com o tempo.
  class SaveUser
    def self.create(attributes:, permissions:, grants:, actor:)
      # O convidado nasce na organização de quem convida; o papel de administrador da
      # organização nunca vem daqui (só a plataforma o atribui, por outro caminho).
      user = User.new(attributes.merge(created_by: actor, must_change_password: true,
        organization: actor.organization))
      user.permissions = allowed_permissions(permissions, actor)
      apply(user:, grants:, actor:, provisional_password: true)
    end

    def self.update(user:, attributes:, permissions:, grants:, actor:)
      before = { permissions: user.permissions.dup, grants: grant_pairs(user) }
      user.assign_attributes(attributes)
      user.permissions = allowed_permissions(permissions, actor)
      result = apply(user:, grants:, actor:, provisional_password: false)

      # Mudança de permissão ou de escopo derruba as sessões abertas: quem perdeu acesso continuaria dentro até a sessão expirar sozinha.
      after = { permissions: user.permissions, grants: grant_pairs(user) }
      if before != after
        user.revoke_sessions!
        Audit.record("user.access_changed", user: actor, record: user,
          metadata: { permissoes_antes: before[:permissions], permissoes_depois: user.permissions,
            escopos_antes: before[:grants].size, escopos_depois: after[:grants].size })
      end
      result
    end

    def self.apply(user:, grants:, actor:, provisional_password:)
      ApplicationRecord.transaction do
        user.save!
        replace_grants(user:, grants: allowed_grants(grants, actor), actor:)
      end
      Audit.record(provisional_password ? "user.created" : "user.updated", user: actor, record: user,
        metadata: { alvo: user.email_address })
      user
    end
    private_class_method :apply

    # Ninguém concede permissão que não tem — e "ter" é o que permitted? diz, então quem
    # administra passa direto porque tem todas.
    def self.allowed_permissions(permissions, actor)
      requested = Permission.with_implied(Array(permissions).map(&:to_s) & Permission::KEYS)
      requested.select { |key| actor.permitted?(key) }
    end
    private_class_method :allowed_permissions

    # Nem escopo além do próprio: conceder um Master inteiro exige tê-lo inteiro; conceder
    # um MIC exige ter o Master dele ou exatamente aquele MIC.
    def self.allowed_grants(grants, actor)
      scope = AccessScope.for(actor)
      Array(grants).select do |grant|
        channel_id = grant[:channel_id].to_i
        sub_channel_id = grant[:sub_channel_id].presence&.to_i
        if sub_channel_id
          scope.whole_channel_ids.include?(channel_id) || scope.sub_channel_ids.include?(sub_channel_id)
        else
          scope.whole_channel_ids.include?(channel_id)
        end
      end
    end
    private_class_method :allowed_grants

    # Conceder o Master inteiro apaga as concessões de MIC dele: sem isso, o escopo
    # carregaria um recorte fino que já não recorta nada.
    # A concessão de Master ou MIC apagado não aparece no formulário e fica guardada: é ela
    # que devolve o acesso quando a plataforma restaura.
    def self.replace_grants(user:, grants:, actor:)
      user.access_grants.joins(:channel).merge(Channel.active)
        .left_joins(:sub_channel).where(sub_channels: { deleted_at: nil }).destroy_all
      grants.each do |grant|
        user.access_grants.create!(channel_id: grant[:channel_id],
          sub_channel_id: grant[:sub_channel_id].presence, created_by: actor)
      end
      whole_channel_ids = user.access_grants.full_channels.pluck(:channel_id)
      user.access_grants.partial.where(channel_id: whole_channel_ids).destroy_all
    end
    private_class_method :replace_grants

    def self.grant_pairs(user)
      user.access_grants.reload.pluck(:channel_id, :sub_channel_id).sort
    end
    private_class_method :grant_pairs
  end
end
