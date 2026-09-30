# Quem administra acessos. Todas as regras daqui existem para impedir a mesma coisa: alguém
# conceder a si mesmo, ou a outro, mais do que recebeu.
#
# As mesmas regras estão no modelo (User#validate_grant_by). Repetição proposital: a policy
# protege a tela, e o modelo protege o console, o seed e um job futuro — a policy não
# alcança nenhum deles.
class UserPolicy < ApplicationPolicy
  def index? = permitted?(Permission::USERS_INVITE)
  def show? = index? && reachable?
  def create? = index?
  def new? = create?

  # Não se edita quem tem algo que você não tem. Sem esta regra, um admin de um MIC
  # reiniciaria o segundo fator do super admin e entraria como ele.
  def update? = index? && reachable? && !outranks_me?
  alias_method :edit?, :update?
  alias_method :reset_mfa?, :update?
  alias_method :reset_password?, :update?

  # Desativar é o "excluir" deste portal: a conta some do uso, mas o histórico dela
  # continua na trilha, que é o que permite auditar depois.
  def deactivate? = update? && record != user

  private

  def reachable?
    return true if user&.platform_admin?
    return false if record.nil?
    return true if record == user
    # Ninguém alcança uma conta da plataforma, e ninguém alcança fora da própria organização.
    return false if record.platform_admin? || record.organization_id != user.organization_id
    return true if user.organization_admin?

    # O delegado administra quem está dentro do escopo dele — e quem ainda não tem escopo
    # nenhum, que é o estado de um convite recém-criado por ele.
    alvo = AccessScope.for(record)
    alvo.empty? || (alvo.channel_ids - AccessScope.for(user).channel_ids).empty?
  end

  # "Tem algo que eu não tenho": plataforma, administrador da organização, permissão ou
  # escopo além do meu. Um administrador da organização não edita outro: quem mexe neles é
  # a plataforma.
  def outranks_me?
    return false if user&.platform_admin?
    return true if record&.platform_admin?
    return record.organization_admin? && record != user if user.organization_admin?
    return true if record&.organization_admin?
    return true if (record.permissions - user.permissions).any?

    (AccessScope.for(record).channel_ids - AccessScope.for(user).channel_ids).any?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.permitted?(Permission::USERS_INVITE)

      # A organização recorta primeiro: o resto é quem, dentro dela, o ator alcança.
      base = scope.where(organization_id: user.organization_id)
      return base if user.organization_admin?

      # Quem o delegado enxerga: ele mesmo, os que criou e os que estão no escopo dele.
      ids = AccessGrant.where(channel_id: AccessScope.for(user).channel_ids).select(:user_id)
      base.where(id: user.id).or(base.where(created_by_id: user.id)).or(base.where(id: ids))
    end
  end
end
