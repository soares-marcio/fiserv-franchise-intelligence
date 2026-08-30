require "test_helper"

class BinImport::CutoffTest < ActiveSupport::TestCase
  test "uses the last day with value in a partial month" do
    assert_equal 24, BinImport::Cutoff.day([ revenue_row(24) ])
  end

  test "uses day 31 when the month has value through its last day" do
    assert_equal 31, BinImport::Cutoff.day([ revenue_row(31) ])
  end

  private

  def revenue_row(last_day)
    (1..31).to_h do |day|
      [ format("DIA %02d", day), day == last_day ? 10 : 0 ]
    end
  end
end
