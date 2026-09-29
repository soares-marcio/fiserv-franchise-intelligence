class ImportBatchPolicy < ApplicationPolicy
  def index? = permitted?(Permission::BATCHES_READ)

  # Ver um lote específico exige, além da chave, que ele esteja ao alcance: os próprios
  # envios e os que alguém liberou nominalmente.
  def show? = index? && reachable?
  alias_method :download_source_file?, :show?

  def create? = permitted?(Permission::BATCHES_UPLOAD)

  # Mexer num lote é só para quem o enviou — mesmo quem tem o lote liberado para ver não
  # reprocessa nem descarta. Descartar é irreversível, e reprocessar reescreve a
  # consolidação do Master inteiro.
  def update_cutoff? = permitted?(Permission::BATCHES_ADJUST) && own?
  alias_method :reprocess?, :update_cutoff?

  def destroy? = permitted?(Permission::BATCHES_DISCARD) && own?

  def review? = permitted?(Permission::BATCHES_APPROVE) && whole_channel?
  alias_method :approve?, :review?
  alias_method :reject?, :review?

  # Liberar o arquivo a outra pessoa é administrar acesso: a chave é a de convidar, o lote
  # precisa estar ao alcance e o Master precisa ser inteiro — quem tem um MIC não repassa
  # a carteira toda.
  def grant? = permitted?(Permission::USERS_INVITE) && reachable? && whole_channel?
  alias_method :revoke?, :grant?

  private

  def own?
    user&.platform_admin? || record&.uploaded_by_id == user&.id
  end

  def reachable?
    return true if user&.platform_admin?
    return false if record.nil?

    return true if record.pending_review? && review?

    own? || BatchGrant.exists?(user_id: user&.id, import_batch_id: record.id)
  end

  # Aprovar depende do canal do lote, e não de quem o enviou: quem revisa é o operador
  # autorizador daquela carteira. E da carteira **inteira**: a revisão mostra o diff do
  # Master todo, e um aprovador com um MIC só veria os outros nove (homologação de
  # 29/09/2026).
  def whole_channel?
    return true if user&.platform_admin?
    return false if record.nil? || record.channel_id.nil?

    AccessScope.for(user).whole?(record.channel_id)
  end

  # Só os próprios envios e os liberados. Lote ainda sem canal (o canal só é resolvido
  # depois do parse) aparece para quem o enviou — senão sumiria justamente enquanto está
  # sendo processado.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.platform_admin?

      alcance = scope.where(uploaded_by_id: user&.id)
        .or(scope.where(id: BatchGrant.where(user_id: user&.id).select(:import_batch_id)))
      return alcance unless user&.permitted?(Permission::BATCHES_APPROVE)

      # Quem aprova enxerga também o que está esperando decisão nos Masters que tem
      # inteiros — sem isso, revisar exigiria uma liberação para cada arquivo.
      alcance.or(scope.where(status: "pending_review", channel_id: AccessScope.for(user).full_channel_ids))
    end
  end
end
