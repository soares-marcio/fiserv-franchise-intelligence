class ImportBatchPolicy < ApplicationPolicy
  def index? = permitted?(Permission::BATCHES_READ)
  alias_method :show?, :index?

  # Baixar o arquivo enviado é ver a carteira inteira de um Master de uma vez; anda junto
  # com ver o lote, mas fica nomeado à parte para quem ler a policy não ter dúvida.
  alias_method :download_source_file?, :index?

  def create? = permitted?(Permission::BATCHES_UPLOAD)

  def update_cutoff? = permitted?(Permission::BATCHES_ADJUST)
  alias_method :reprocess?, :update_cutoff?

  def destroy? = permitted?(Permission::BATCHES_DISCARD)

  def review? = permitted?(Permission::BATCHES_APPROVE)
  alias_method :approve?, :review?
  alias_method :reject?, :review?
end
