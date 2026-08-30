class PartitionDailyRevenues < ActiveRecord::Migration[8.1]
  def up
    return if partitioned?

    drop_table :daily_revenues
    execute <<~SQL
      CREATE TABLE daily_revenues (
        id bigserial NOT NULL,
        import_batch_id bigint NOT NULL REFERENCES import_batches(id),
        channel_id bigint NOT NULL REFERENCES channels(id),
        establishment_id bigint NOT NULL REFERENCES establishments(id),
        period date NOT NULL,
        day integer NOT NULL,
        amount numeric(18,2) NOT NULL,
        provisional boolean NOT NULL,
        created_at timestamp(6) without time zone NOT NULL,
        updated_at timestamp(6) without time zone NOT NULL,
        CONSTRAINT daily_revenues_valid_day CHECK (day BETWEEN 1 AND 31)
      ) PARTITION BY RANGE (period);
      CREATE TABLE daily_revenues_default PARTITION OF daily_revenues DEFAULT;
    SQL
    add_index :daily_revenues, %i[import_batch_id establishment_id period day], unique: true,
      name: "index_daily_revenues_unique_snapshot_day"
    add_index :daily_revenues, %i[channel_id period day]
    add_index :daily_revenues, :import_batch_id
    add_index :daily_revenues, :channel_id
    add_index :daily_revenues, :establishment_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def partitioned?
    connection.select_value(<<~SQL)
      SELECT 1
      FROM pg_partitioned_table pt
      JOIN pg_class c ON c.oid = pt.partrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'daily_revenues'
    SQL
  end
end
