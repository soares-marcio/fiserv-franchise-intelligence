class DailyRevenuePartitions
  def self.ensure!(competencia)
    start_date = competencia.beginning_of_month
    end_date = start_date.next_month
    suffix = start_date.strftime("%Y%m")
    connection = ApplicationRecord.connection
    name = connection.quote_table_name("daily_revenues_#{suffix}")

    ApplicationRecord.transaction do
      ensure_default_partition!(connection)
      connection.execute("LOCK TABLE daily_revenues_default IN ACCESS EXCLUSIVE MODE")
      connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{name}
        PARTITION OF daily_revenues
        FOR VALUES FROM (#{connection.quote(start_date)}) TO (#{connection.quote(end_date)})
      SQL
    end
  end

  def self.ensure_default_partition!(connection)
    return if connection.table_exists?("daily_revenues_default")

    connection.execute(<<~SQL)
      CREATE TABLE daily_revenues_default PARTITION OF daily_revenues DEFAULT
    SQL
  end
end
