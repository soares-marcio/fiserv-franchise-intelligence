class MetabaseRole
  NAME = "metabase_ro"
  VIEWS = AuditViews::NAMES
  WRITABLE_TABLES = %w[raw_import_rows import_batches daily_revenues map_snapshots].freeze

  def self.ensure!
    connection = ApplicationRecord.connection
    password = connection.quote(ENV.fetch("METABASE_RO_PASSWORD", "metabase_ro"))
    create_role!(connection, password)
    connection.execute("ALTER ROLE #{NAME} WITH LOGIN PASSWORD #{password}")
    connection.execute(
      "GRANT CONNECT ON DATABASE #{connection.quote_table_name(connection.current_database)} TO #{NAME}"
    )
    connection.execute("GRANT USAGE ON SCHEMA public TO #{NAME}")
    connection.execute("REVOKE ALL ON ALL TABLES IN SCHEMA public FROM #{NAME}")
    VIEWS.each do |view|
      connection.execute("GRANT SELECT ON #{connection.quote_table_name(view)} TO #{NAME}")
    end
  end

  def self.role_exists?
    ApplicationRecord.connection.select_value(
      "SELECT 1 FROM pg_roles WHERE rolname = #{ApplicationRecord.connection.quote(NAME)}"
    ).present?
  end

  def self.create_role!(connection, password)
    return if role_exists?

    connection.execute("CREATE ROLE #{NAME} LOGIN PASSWORD #{password}")
  rescue ActiveRecord::StatementInvalid => error
    raise unless /already exists/i.match?(error.message)
  end
  private_class_method :create_role!
end
