class AddReviewReasonsToImportBatches < ActiveRecord::Migration[8.1]
  STATUSES = %w[pending validated failed superseded pending_review rejected].freeze
  PREVIOUS_STATUSES = %w[pending validated failed superseded].freeze

  def up
    # Por que este lote parou para revisão. Guardado no lote, e não recalculado na tela: a
    # carteira muda com o tempo, e o motivo precisa ser o que valia no momento do envio.
    unless column_exists?(:import_batches, :review_reasons)
      add_column :import_batches, :review_reasons, :string, array: true, null: false, default: [],
        comment: "Motivos que levaram o lote à revisão: sem permissão de aprovar, remoção de ECs, troca de MIC, queda de faturamento"
    end

    # O CHECK de status é a guarda que impede um valor inventado entrar por console ou por
    # código novo; os dois estados da quarentena entram nele.
    replace_status_check(STATUSES)
  end

  def down
    replace_status_check(PREVIOUS_STATUSES)
    remove_column :import_batches, :review_reasons
  end

  private

  def replace_status_check(statuses)
    lista = statuses.map { |status| connection.quote(status) }.join(", ")
    remove_check_constraint :import_batches, name: "import_batches_valid_status"
    add_check_constraint :import_batches, "status IN (#{lista})", name: "import_batches_valid_status"
  end
end
