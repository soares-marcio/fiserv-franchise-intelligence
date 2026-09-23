module UsersHelper
  def user_status_badge(user)
    return content_tag(:span, "Desativado", class: "badge badge-ghost") unless user.active?
    return content_tag(:span, "Bloqueado", class: "badge badge-error") if user.locked?
    # Convite ainda não usado: senha por trocar ou segundo fator por cadastrar.
    unless user.mfa_enabled? && !user.must_change_password?
      return content_tag(:span, "Primeiro acesso pendente", class: "badge badge-warning")
    end

    content_tag(:span, "Ativo", class: "badge badge-success")
  end

  def user_scope_summary(user)
    return "Tudo" if user.super_admin?

    grants = user.access_grants
    return "Nada" if grants.empty?

    grants.map { |grant| grant.sub_channel_id ? grant.sub_channel&.name : grant.channel&.name }
      .compact.to_sentence
  end

  def user_permissions_summary(user)
    return "Todas" if user.super_admin?
    return "Nenhuma" if user.permissions.empty?

    user.permissions.map { |chave| Permission.label(chave) }.to_sentence
  end
end
