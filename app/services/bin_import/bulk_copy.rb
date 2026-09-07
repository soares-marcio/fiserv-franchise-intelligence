module BinImport
  # Carga em massa por COPY. Nas quatro tabelas grandes do import (~11 mil linhas cada para a
  # carteira real), o ActiveRecord gastava mais tempo montando o INSERT multilinha do que o
  # Postgres executando-o. Cada linha é um Hash com as mesmas chaves, como em insert_all!.
  module BulkCopy
    # Os encoders convertem em C e levam Time para UTC: o fuso da aplicação nunca chega ao banco.
    TYPE_MAP = PG::TypeMapByClass.new.tap do |map|
      map[Integer] = PG::TextEncoder::Integer.new
      map[BigDecimal] = PG::TextEncoder::Numeric.new
      map[Date] = PG::TextEncoder::Date.new
      map[Time] = map[ActiveSupport::TimeWithZone] = PG::TextEncoder::TimestampUtc.new
      map[TrueClass] = map[FalseClass] = PG::TextEncoder::Boolean.new
    end
    private_constant :TYPE_MAP

    # Equivalente a insert_all!: toda linha entra, e conflito é erro.
    def self.insert(model, rows)
      return if rows.empty?

      copy_into(model.connection, model.quoted_table_name, rows)
    end

    # Equivalente a upsert_all(unique_by:): em conflito sobrescreve todas as colunas fora da
    # chave, created_at inclusive, como o ActiveRecord faz.
    def self.upsert(model, rows, conflict_columns:)
      return if rows.empty?

      conn = model.connection
      columns = rows.first.keys
      temp = "#{model.table_name}_copy"
      updates = (columns - conflict_columns).map do |column|
        "#{conn.quote_column_name(column)} = EXCLUDED.#{conn.quote_column_name(column)}"
      end
      model.transaction do
        conn.execute("CREATE TEMP TABLE #{temp} (LIKE #{model.quoted_table_name})")
        copy_into(conn, temp, rows)
        conn.execute(<<~SQL)
          INSERT INTO #{model.quoted_table_name} (#{column_list(conn, columns)})
          SELECT #{column_list(conn, columns)} FROM #{temp}
          ON CONFLICT (#{column_list(conn, conflict_columns)}) DO UPDATE SET #{updates.join(", ")}
        SQL
        conn.execute("DROP TABLE #{temp}")
      end
    end

    def self.copy_into(conn, table, rows)
      columns = rows.first.keys
      raw = conn.raw_connection
      encoder = PG::TextEncoder::CopyRow.new(type_map: TYPE_MAP)
      raw.copy_data("COPY #{table} (#{column_list(conn, columns)}) FROM STDIN", encoder) do
        rows.each { |row| raw.put_copy_data(row.values_at(*columns)) }
      end
      # O COPY passa por fora do ActiveRecord, que não fica sabendo que a tabela mudou.
      conn.clear_query_cache
    end

    def self.column_list(conn, columns)
      columns.map { |column| conn.quote_column_name(column) }.join(", ")
    end

    private_class_method :copy_into, :column_list
  end
end
