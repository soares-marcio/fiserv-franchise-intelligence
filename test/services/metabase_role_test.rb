require "test_helper"

class MetabaseRoleTest < ActiveSupport::TestCase
  setup { MetabaseRole.ensure! }

  test "can select audit views and cannot select writable tables" do
    connection = ApplicationRecord.connection

    AuditViews::NAMES.each do |view|
      assert privilege?(connection, view, "SELECT"), "expected SELECT on #{view}"
    end

    MetabaseRole::WRITABLE_TABLES.each do |table|
      refute privilege?(connection, table, "SELECT"), "expected no SELECT on #{table}"
    end
  end

  private

  def privilege?(connection, relation, privilege)
    connection.select_value(
      "SELECT has_table_privilege(#{connection.quote(MetabaseRole::NAME)}, " \
        "#{connection.quote(relation)}, #{connection.quote(privilege)})"
    )
  end
end
