# pg_dump from PostgreSQL 17 emits SET transaction_timeout; the Compose image is PG 16.
Rake::Task["db:schema:dump"].enhance do
  path = Rails.root.join("db/structure.sql")
  next unless path.exist?

  sql = File.read(path).gsub(/^SET transaction_timeout = .*$\n/, "")
  File.write(path, sql)
end
