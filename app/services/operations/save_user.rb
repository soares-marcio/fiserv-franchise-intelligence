module Operations
  # Criar e editar usuário, com as regras que impedem escalonamento de privilégio.
  #
  # Ficam aqui, e não só na policy, porque a policy protege a tela: console, seed e job
  # passariam por fora. E ficam num lugar só para as duas checagens — permissões e escopo —
  # não divergirem com o tempo.
  class SaveUser
    def self.create(attributes:, permissions:, grants:, actor:)
      user = User.new(attributes.merge(created_by: actor, must_change_password: true))
      user.permissions = allowed_permissions(permissions, actor)
      apply(user:, grants:, actor:, senha_provisoria: true)
    end

    def self.update(user:, attributes:, permissions:, grants:, actor:)
      antes = { permissions: user.permissions.dup, grants: grant_pairs(user), platform_admin: user.platform_admin? }
      user.assign_attributes(attributes)
      user.permissions = allowed_permissions(permissions, actor)
      resultado = apply(user:, grants:, actor:, senha_provisoria: false)

      # Mudança de permissão, de escopo ou de administrador geral derruba as sessões
      # abertas: quem perdeu acesso continuaria dentro até a sessão expirar sozinha.
      depois = { permissions: user.permissions, grants: grant_pairs(user), platform_admin: user.platform_admin? }
      if antes != depois
        user.revoke_sessions!
        Audit.record("user.access_changed", user: actor, record: user,
          metadata: { permissoes_antes: antes[:permissions], permissoes_depois: user.permissions,
            escopos_antes: antes[:grants].size, escopos_depois: depois[:grants].size,
            admin_geral_antes: antes[:platform_admin], admin_geral_depois: depois[:platform_admin] })
      end
      resultado
    end

    def self.apply(user:, grants:, actor:, senha_provisoria:)
      ApplicationRecord.transaction do
        user.save!
        replace_grants(user:, grants: allowed_grants(grants, actor), actor:)
      end
      Audit.record(senha_provisoria ? "user.created" : "user.updated", user: actor, record: user,
        metadata: { alvo: user.email_address })
      user
    end
    private_class_method :apply

    # Ninguém concede permissão que não tem. O super admin passa direto porque tem todas.
    def self.allowed_permissions(permissions, actor)
      pedidas = Array(permissions).map(&:to_s) & Permission::KEYS
      return pedidas if actor.platform_admin?

      pedidas & actor.permissions
    end
    private_class_method :allowed_permissions

    # Nem escopo além do próprio: conceder um Master inteiro exige tê-lo inteiro; conceder
    # um MIC exige ter o Master dele ou exatamente aquele MIC.
    def self.allowed_grants(grants, actor)
      return Array(grants) if actor.platform_admin?

      escopo = AccessScope.for(actor)
      Array(grants).select do |grant|
        channel_id = grant[:channel_id].to_i
        sub_channel_id = grant[:sub_channel_id].presence&.to_i
        if sub_channel_id
          escopo.full_channel_ids.include?(channel_id) || escopo.sub_channel_ids.include?(sub_channel_id)
        else
          escopo.full_channel_ids.include?(channel_id)
        end
      end
    end
    private_class_method :allowed_grants

    # Conceder o Master inteiro apaga as concessões de MIC dele: sem isso, o escopo
    # carregaria um recorte fino que já não recorta nada.
    def self.replace_grants(user:, grants:, actor:)
      user.access_grants.destroy_all
      grants.each do |grant|
        user.access_grants.create!(channel_id: grant[:channel_id],
          sub_channel_id: grant[:sub_channel_id].presence, created_by: actor)
      end
      inteiros = user.access_grants.full_channels.pluck(:channel_id)
      user.access_grants.partial.where(channel_id: inteiros).destroy_all
    end
    private_class_method :replace_grants

    def self.grant_pairs(user)
      user.access_grants.reload.pluck(:channel_id, :sub_channel_id).sort
    end
    private_class_method :grant_pairs
  end
end
