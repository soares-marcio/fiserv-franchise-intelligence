class ImportBinFileJob < ApplicationJob
  queue_as :default

  # Um import por vez: dois em paralelo disputam o lock da partição, a consolidação e o
  # refresh das views. O período padrão do semáforo é de 3 minutos, contra os ~40 segundos
  # que os imports reais levaram até agora.
  limits_concurrency to: 1, key: "bin_import"

  # Só falha de conexão é transitória; planilha errada não melhora na segunda tentativa.
  RETRYABLE = [ ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad ].freeze
  ATTEMPTS = 3

  # O bloco só roda quando as tentativas acabam: é ali que a falha vira "falhou" na tela.
  retry_on(*RETRYABLE, attempts: ATTEMPTS, wait: :polynomially_longer) do |job, error|
    job.mark_batch_failed(error)
    raise error
  end

  def perform(batch_id)
    batch = ImportBatch.find(batch_id)
    batch.source_file.blob.open do |file|
      BinImport::Importer.new(file.path, source_filename: batch.source_file.filename.to_s).call
    end
  rescue StandardError => error
    # Sem isto, uma falha antes do parse não deixaria rastro na tela de importação. Falha
    # transitória fica de fora: marcar "falhou" com nova tentativa a caminho faria o usuário
    # reenviar o arquivo à toa. Quem a marca, se as tentativas acabarem, é o bloco do retry_on.
    mark_batch_failed(error) unless RETRYABLE.any? { |klass| error.is_a?(klass) }
    raise
  end

  def mark_batch_failed(error)
    ImportBatch.find_by(id: arguments.first)&.update(status: "failed", validation_errors: [ error.message ])
  end
end
