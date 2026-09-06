require "test_helper"

class MetabaseRoleTest < ActiveSupport::TestCase
  setup { MetabaseRole.ensure! }

  test "consegue ler as views de auditoria e não consegue ler as tabelas graváveis" do
    connection = ApplicationRecord.connection

    AuditViews::NAMES.each do |view|
      assert privilege?(connection, view, "SELECT"), "expected SELECT on #{view}"
    end

    # Amostra de tabelas do app: o papel só enxerga as views, nunca a base.
    %w[raw_import_rows import_batches daily_revenues map_snapshots].each do |table|
      refute privilege?(connection, table, "SELECT"), "expected no SELECT on #{table}"
    end
  end

  test "usa a senha do ambiente quando definida" do
    with_env("METABASE_RO_PASSWORD" => "s3nha") do
      assert_equal "s3nha", MetabaseRole.readonly_password
    end
  end

  # O papel é do cluster, compartilhado pelos bancos de todos os ambientes: um seed em
  # development sem a variável trocaria a senha que o Metabase da stack está usando pela
  # padrão. Só em teste, onde a CI não a define, a senha é indiferente.
  test "fora de teste, sem a variável, falha em vez de cair na senha padrão" do
    with_env("METABASE_RO_PASSWORD" => nil) do
      assert_equal "metabase_ro", MetabaseRole.readonly_password
      with_rails_env("development") do
        assert_raises(KeyError) { MetabaseRole.readonly_password }
      end
    end
  end

  private

  def with_rails_env(name)
    previous = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = previous
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def privilege?(connection, relation, privilege)
    connection.select_value(
      "SELECT has_table_privilege(#{connection.quote(MetabaseRole::NAME)}, " \
        "#{connection.quote(relation)}, #{connection.quote(privilege)})"
    )
  end
end
