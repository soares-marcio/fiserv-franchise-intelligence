ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    # Sem paralelismo por processo: os workers forkados dão segfault no gem pg
    # (pg/connection.rb connect_start) e o processo pai fica pendurado no DRb.
    # A suíte roda em ~35s em processo único; PARALLEL_WORKERS ainda sobrescreve.
    parallelize(workers: 1)

    # As views materializadas só precisam ser atualizadas nos testes que as leem.
    def refresh_audit_views
      AuditViews.refresh!
    end

    def import_synthetic_workbook(lojas: BinWorkbook.default_lojas, filename: "BIN_TESTE_20260811.xlsx")
      path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
      BinWorkbook.write(path, lojas:)
      BinImport::Importer.new(path, source_filename: filename).call
    ensure
      File.delete(path) if path && File.exist?(path)
    end
  end
end
