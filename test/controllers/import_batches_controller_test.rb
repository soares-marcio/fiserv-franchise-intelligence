require "test_helper"

class ImportBatchesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "lista os lotes mais recentes" do
    batch = import_synthetic_workbook

    get import_batches_path

    assert_response :success
    assert_select "td", text: /#{batch.source_filename}/
  end

  test "mostra um lote pela uuid pública" do
    batch = import_synthetic_workbook

    get import_batch_path(batch)

    assert_response :success
  end

  test "enfileira a importação de um xlsx" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-upload.xlsx")
    BinWorkbook.write(path)

    assert_enqueued_with(job: ImportBinFileJob) do
      post import_batches_path, params: { file: upload(path) }
    end

    assert_redirected_to import_batches_path
    assert_equal "Importação enfileirada.", flash[:notice]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "recusa arquivo que não é xlsx" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-nota.txt")
    File.write(path, "conteúdo")

    assert_no_enqueued_jobs(only: ImportBinFileJob) do
      post import_batches_path, params: { file: upload(path, "text/plain") }
    end

    assert_equal "Envie um arquivo .xlsx.", flash[:alert]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "recusa envio sem arquivo" do
    post import_batches_path

    assert_redirected_to import_batches_path
    assert_equal "Selecione um arquivo.", flash[:alert]
  end

  test "ajusta o dia de corte e propaga para a cobertura" do
    batch = import_synthetic_workbook

    patch update_cutoff_import_batch_path(batch), params: { max_known_day: 15 }

    assert_equal "Dia de corte atualizado.", flash[:notice]
    assert_equal 15, batch.reload.current_month_cutoff_day
    assert_equal 15, PeriodCoverage.find_by!(
      channel_id: batch.channel_id, period: batch.current_period
    ).max_known_day
  end

  test "recusa dia de corte fora do intervalo" do
    batch = import_synthetic_workbook

    patch update_cutoff_import_batch_path(batch), params: { max_known_day: 40 }

    assert_equal "Dia de corte deve estar entre 1 e 31", flash[:alert]
    assert_equal BinWorkbook.cutoff_day, batch.reload.current_month_cutoff_day
  end

  test "reprocessa um lote validado" do
    batch = import_synthetic_workbook

    post reprocess_import_batch_path(batch)

    assert_equal "Lote reprocessado.", flash[:notice]
  end

  test "recusa reprocessar lote que não foi validado" do
    batch = import_synthetic_workbook
    batch.update!(status: "failed")

    post reprocess_import_batch_path(batch)

    assert_equal "Só é possível reprocessar lote validado", flash[:alert]
  end

  test "upload cria o lote antes do parse, para a falha ter onde aparecer" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-upload.xlsx")
    BinWorkbook.write(path)

    assert_difference -> { ImportBatch.count }, 1 do
      post import_batches_path, params: { file: upload(path) }
    end
    batch = ImportBatch.last

    assert_equal "pending", batch.status
    assert_equal path.basename.to_s, batch.source_filename
    assert_nil batch.channel_id
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "falha antes do parse marca o lote e mostra o motivo na tela" do
    batch = ImportBatch.create!(
      source_filename: "quebrado.xlsx", file_checksum: "checksum-quebrado", status: "pending"
    )

    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      ImportBinFileJob.perform_now(batch.id, "assinatura-invalida")
    end

    assert_equal "failed", batch.reload.status
    assert_predicate batch.validation_errors, :any?

    get import_batch_path(batch)
    assert_response :success
    assert_select "div.alert-error", text: /A importação falhou/
    assert_select "li", text: /#{Regexp.escape(batch.validation_errors.first)}/
  end

  test "recusa reenviar um arquivo já importado" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-upload.xlsx")
    BinWorkbook.write(path)
    post import_batches_path, params: { file: upload(path) }
    ImportBatch.last.update!(status: "validated")

    assert_no_difference -> { ImportBatch.count } do
      post import_batches_path, params: { file: upload(path) }
    end
    assert_equal "Arquivo já importado", flash[:alert]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "avisa que a importação está em curso e que a tela atualiza sozinha" do
    ImportBatch.create!(
      source_filename: "em-curso.xlsx", file_checksum: "checksum-em-curso", status: "pending"
    )

    get import_batches_path

    assert_select "div.alert-info", text: /esta tela avisa\s+sozinha quando terminar/
    assert_select "turbo-cable-stream-source"
  end

  test "avisa quando um lote pendente passou do tempo esperado" do
    batch = ImportBatch.create!(
      source_filename: "travado.xlsx", file_checksum: "checksum-travado", status: "pending"
    )
    batch.update_column(:created_at, 20.minutes.ago)

    get import_batches_path

    assert_select "div.alert-warning", text: /verifique se o worker está no ar/
  end

  test "mostra há quantos dias não chega arquivo e alerta a partir de 12" do
    recente = import_synthetic_workbook
    recente.update_column(:created_at, 3.days.ago)

    get import_batches_path
    assert_select ".metric-value", text: "há 3 dias"
    assert_select ".metric-card[data-tone=?]", "green"
    assert_not ImportBatch.stale?

    recente.update_column(:created_at, ImportBatch::STALE_AFTER_DAYS.days.ago)

    get import_batches_path
    assert_select ".metric-value", text: "há #{ImportBatch::STALE_AFTER_DAYS} dias"
    assert_select ".metric-card[data-tone=?]", "rose"
    assert ImportBatch.stale?
  end

  test "sem nenhum lote validado a carteira já conta como desatualizada" do
    get import_batches_path

    assert_select ".metric-value", text: "Nunca"
    assert ImportBatch.stale?
  end

  private

  def upload(path, content_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    Rack::Test::UploadedFile.new(path, content_type)
  end
end
