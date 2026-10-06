require "test_helper"

class LogRetentionTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@dir) }

  test "apaga o arquivo girado há mais de 30 dias e guarda o resto" do
    old = touch("web.log.20260801", 31.days.ago)
    recent = touch("web.log.20260920", 29.days.ago)
    live = touch("web.log", 40.days.ago)
    keep = touch(".keep", 40.days.ago)

    LogRetention.purge(@dir)

    assert_not File.exist?(old)
    assert File.exist?(recent)
    assert File.exist?(live), "o arquivo em uso nunca é apagado, por mais velho que pareça"
    assert File.exist?(keep)
  end

  test "pasta inexistente não é erro: no Mac o log não vai para arquivo" do
    assert_nothing_raised { LogRetention.purge(File.join(@dir, "nao-existe")) }
  end

  private

  def touch(name, time)
    File.join(@dir, name).tap do |path|
      File.write(path, "linha\n")
      File.utime(time.to_time, time.to_time, path)
    end
  end
end
