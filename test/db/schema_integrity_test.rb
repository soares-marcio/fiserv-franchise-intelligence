require "test_helper"

# O banco de teste nasce do db/structure.sql, o mesmo arquivo que produção e qualquer banco
# recriado recebem. Se algo que a aplicação precisa não está nele, este teste falha antes de
# um ambiente novo descobrir em silêncio, como aconteceu com as tabelas do Solid Cable.
class SchemaIntegrityTest < ActiveSupport::TestCase
  SOLID_QUEUE_TABLES = %w[
    solid_queue_jobs solid_queue_ready_executions solid_queue_scheduled_executions
    solid_queue_claimed_executions solid_queue_failed_executions solid_queue_blocked_executions
    solid_queue_recurring_executions solid_queue_recurring_tasks solid_queue_processes
    solid_queue_pauses solid_queue_semaphores
  ].freeze

  test "tabelas dos adapters Solid Queue, Solid Cable e Solid Cache existem no schema" do
    (SOLID_QUEUE_TABLES + %w[solid_cable_messages solid_cache_entries]).each do |table|
      assert connection.table_exists?(table), "tabela #{table} ausente no structure.sql"
    end
  end

  test "Solid Cable consegue gravar um broadcast" do
    assert_difference -> { SolidCable::Message.count }, 1 do
      SolidCable::Message.broadcast("schema-integrity", "ping")
    end
  end

  test "Solid Cache consegue gravar e ler" do
    store = SolidCache::Store.new
    store.write("schema-integrity", "ok")

    assert_equal "ok", store.read("schema-integrity")
  end

  test "Solid Queue consegue enfileirar" do
    assert_difference -> { SolidQueue::Job.count }, 1 do
      SolidQueue::Job.create!(queue_name: "default", class_name: "ApplicationJob", arguments: {})
    end
  end

  test "as seis views de auditoria existem, nascem sem dados e aceitam refresh" do
    AuditViews::NAMES.each do |view|
      assert connection.select_value(
        "SELECT 1 FROM pg_matviews WHERE matviewname = #{connection.quote(view)}"
      ), "view materializada #{view} ausente"
    end

    assert_nothing_raised { AuditViews.refresh! }
    AuditViews::NAMES.each { |view| assert AuditViews.populated?(view), "#{view} não populou" }
  end

  test "daily_revenues é particionada e tem a partição default" do
    assert connection.select_value(
      "SELECT 1 FROM pg_partitioned_table p JOIN pg_class c ON c.oid = p.partrelid WHERE c.relname = 'daily_revenues'"
    ), "daily_revenues não é particionada"
    assert connection.table_exists?("daily_revenues_default"), "partição default ausente"
  end

  test "extensões que o schema usa estão instaladas" do
    %w[pg_trgm].each do |extension|
      assert connection.extension_enabled?(extension), "extensão #{extension} ausente"
    end
  end

  test "as chaves compostas e índices únicos que o código referencia existem" do
    {
      "period_coverages" => "index_period_coverages_on_channel_id_and_period",
      "daily_revenues_consolidated" => "index_daily_revenues_consolidated_primary",
      "monthly_volumes_consolidated" => "index_monthly_volumes_consolidated_primary",
      "conversation_actions" => "index_conversation_actions_on_text"
    }.each do |table, index|
      found = connection.indexes(table).find { |i| i.name == index }
      assert found&.unique, "índice único #{index} ausente em #{table}"
    end
  end

  test "o seed cria o papel do Metabase com acesso só de leitura às views" do
    Rails.application.load_seed

    assert MetabaseRole.role_exists?, "papel #{MetabaseRole::NAME} não criado pelo seed"
    AuditViews::NAMES.each do |view|
      assert connection.select_value(
        "SELECT has_table_privilege(#{connection.quote(MetabaseRole::NAME)}, #{connection.quote(view)}, 'SELECT')"
      ), "#{MetabaseRole::NAME} sem SELECT em #{view}"
    end
    assert_not connection.select_value(
      "SELECT has_table_privilege(#{connection.quote(MetabaseRole::NAME)}, 'import_batches', 'INSERT')"
    ), "#{MetabaseRole::NAME} não pode escrever"
  end

  test "structure.sql em disco é o que está carregado no banco de teste" do
    on_disk = Digest::SHA1.hexdigest(Rails.root.join("db/structure.sql").read)
    loaded = connection.select_value("SELECT value FROM ar_internal_metadata WHERE key = 'schema_sha1'")

    assert_equal on_disk, loaded, "db/structure.sql mudou e o banco de teste ainda não foi recarregado"
  end

  private

  def connection
    ActiveRecord::Base.connection
  end
end
