require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "variation chip names an increase" do
    html = variation_chip(80, 100)

    assert_includes html, "variation-chip--up"
    assert_includes html, 'data-tip="Subiu"'
    assert_includes html, "+25,0%"
    assert_includes html, "<svg"
    refute_includes html, "variation-chip__verb"
  end

  test "variation chip names a decrease" do
    html = variation_chip(100, 60)

    assert_includes html, "variation-chip--down"
    assert_includes html, 'data-tip="Caiu"'
    assert_includes html, "-40,0%"
    refute_includes html, "variation-chip__verb"
  end

  test "variation chip stays empty without a comparable base" do
    html = variation_chip(0, 40)

    assert_includes html, "variation-chip--empty"
    assert_includes html, "—"
    refute_includes html, "subiu"
    refute_includes html, "caiu"
  end

  test "period picker names the selected month range" do
    assert_equal "10 a 20 de agosto de 2026",
      period_picker_label(Date.new(2026, 8, 1), 10, 20)
    assert_equal "24 de agosto de 2026",
      period_picker_label(Date.new(2026, 8, 1), 24, 24)
  end

  test "iso range label names a calendar interval" do
    assert_equal "12/05/2026 a 13/05/2026",
      iso_range_label(Date.new(2026, 5, 12), Date.new(2026, 5, 13))
    assert_equal "Escolher intervalo", iso_range_label(nil, nil)
  end

  test "ignores malformed daily revenue payloads" do
    assert_equal({}, revenue_days_hash("not-json"))
  end
end
