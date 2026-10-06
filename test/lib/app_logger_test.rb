require "test_helper"
require "app_logger"

class AppLoggerTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @io = StringIO.new
  end

  teardown { FileUtils.remove_entry(@dir) }

  # Com um TaggedLogging por destino, o BroadcastLogger repassa o bloco de `tagged` a cada um
  # deles: a requisição inteira rodaria uma vez por destino.
  test "o bloco marcado roda uma vez só, com o arquivo ligado" do
    logger = AppLogger.build(@io, file: File.join(@dir, "web.log"))
    runs = 0

    logger.tagged("req-1") { runs += 1 }

    assert_equal 1, runs
  end

  test "a linha sai marcada na saída padrão e no arquivo" do
    logger = AppLogger.build(@io, file: File.join(@dir, "web.log"))

    logger.tagged("req-1") { logger.info "Started GET /reports" }

    assert_match "[req-1] Started GET /reports", @io.string
    assert_match "[req-1] Started GET /reports", File.read(File.join(@dir, "web.log"))
  end

  test "sem arquivo, só a saída padrão" do
    logger = AppLogger.build(@io, file: nil)

    logger.tagged("req-1") { logger.info "oi" }

    assert_match "[req-1] oi", @io.string
    assert_empty Dir.children(@dir)
  end
end
