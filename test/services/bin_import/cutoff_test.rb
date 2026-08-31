require "test_helper"

class BinImport::CutoffTest < ActiveSupport::TestCase
  test "usa o último dia com valor em mês parcial" do
    assert_equal 24, BinImport::Cutoff.day([ revenue_row(24) ])
  end

  test "usa o dia 31 quando o mês tem valor até o último dia" do
    assert_equal 31, BinImport::Cutoff.day([ revenue_row(31) ])
  end

  private

  def revenue_row(last_day)
    (1..31).to_h do |day|
      [ format("DIA %02d", day), day == last_day ? 10 : 0 ]
    end
  end
end
