class AuditViews
  NAMES = %w[
    audit_revenue_by_sub_channel audit_revenue_by_company audit_stalled_companies
    audit_weekly_revenue audit_pending_actions audit_company_ec_divergence
  ].freeze

  def self.refresh!
    NAMES.each { |name| ApplicationRecord.connection.execute("REFRESH MATERIALIZED VIEW #{name}") }
  end
end
