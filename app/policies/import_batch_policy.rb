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

  def review? = permitted?(Permission::BATCHES_APPROVE) && reachable_channel?
  alias_method :approve?, :review?
  alias_method :reject?, :review?

  private

  def own?
    user&.super_admin? || record&.uploaded_by_id == user&.id
  end

  def reachable?
    return true if user&.super_admin?
    return false if record.nil?

    own? || BatchGrant.exists?(user_id: user&.id, import_batch_id: record.id)
  end

  # Aprovar depende do canal do lote, e não de quem o enviou: quem revisa é o operador
  # autorizador daquela carteira.
  def reachable_channel?
    return true if user&.super_admin?
    return false if record.nil? || record.channel_id.nil?

    AccessScope.for(user).channel_ids.include?(record.channel_id)
  end

  # Só os próprios envios e os liberados. Lote ainda sem canal (o canal só é resolvido
  # depois do parse) aparece para quem o enviou — senão sumiria justamente enquanto está
  # sendo processado.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.super_admin?

      scope.where(uploaded_by_id: user&.id)
        .or(scope.where(id: BatchGrant.where(user_id: user&.id).select(:import_batch_id)))
    end
  end
end
