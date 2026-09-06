class MetabaseRole
  NAME = "metabase_ro"
  VIEWS = AuditViews::NAMES

  def self.ensure!
    connection = ApplicationRecord.connection
    password = connection.quote(readonly_password)
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

  # O papel é do cluster, compartilhado pelos bancos de todos os ambientes, e o ensure! sempre
  # redefine a senha: um seed em development sem a variável trocaria a senha que o Metabase da
  # stack está usando pela padrão. Só em teste, onde a CI não a define, cai no default.
  def self.readonly_password
    password = ENV["METABASE_RO_PASSWORD"]
    return password if password.present?
    raise KeyError, "METABASE_RO_PASSWORD é obrigatória fora do ambiente de teste" unless Rails.env.test?

    "metabase_ro"
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
