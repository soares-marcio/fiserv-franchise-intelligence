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

    patch update_cutoff_import_batch_path(batch), params: { max_dia_conhecido: 15 }

    assert_equal "Dia de corte atualizado.", flash[:notice]
    assert_equal 15, batch.reload.dia_corte_mes_atual
    assert_equal 15, CompetenciaCoverage.find_by!(
      channel_id: batch.channel_id, competencia: batch.competencia_atual
    ).max_dia_conhecido
  end

  test "recusa dia de corte fora do intervalo" do
    batch = import_synthetic_workbook

    patch update_cutoff_import_batch_path(batch), params: { max_dia_conhecido: 40 }

    assert_equal "Dia de corte deve estar entre 1 e 31", flash[:alert]
    assert_equal BinWorkbook.cutoff_day, batch.reload.dia_corte_mes_atual
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

  private

  def upload(path, content_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    Rack::Test::UploadedFile.new(path, content_type)
  end
end
