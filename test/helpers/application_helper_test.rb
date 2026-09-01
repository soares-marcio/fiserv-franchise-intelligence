require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "chip de variação nomeia um aumento" do
    html = variation_chip(80, 100)

    assert_includes html, "variation-chip--up"
    assert_includes html, 'data-tip="Subiu"'
    assert_includes html, "+25,0%"
    assert_includes html, "<svg"
    refute_includes html, "variation-chip__verb"
  end

  test "chip de variação nomeia uma queda" do
    html = variation_chip(100, 60)

    assert_includes html, "variation-chip--down"
    assert_includes html, 'data-tip="Caiu"'
    assert_includes html, "-40,0%"
    refute_includes html, "variation-chip__verb"
  end

  test "chip de variação fica vazio sem base comparável" do
    html = variation_chip(0, 40)

    assert_includes html, "variation-chip--empty"
    assert_includes html, "—"
    refute_includes html, "subiu"
    refute_includes html, "caiu"
  end

  test "seletor de período nomeia a faixa do mês selecionado" do
    assert_equal "10 a 20 de agosto de 2026",
      period_picker_label(Date.new(2026, 8, 1), 10, 20)
    assert_equal "24 de agosto de 2026",
      period_picker_label(Date.new(2026, 8, 1), 24, 24)
  end

  test "rótulo de faixa ISO nomeia um intervalo de calendário" do
    assert_equal "12/05/2026 a 13/05/2026",
      iso_range_label(Date.new(2026, 5, 12), Date.new(2026, 5, 13))
    assert_equal "Escolher intervalo", iso_range_label(nil, nil)
  end

  test "ignora payloads malformados de faturamento diário" do
    assert_equal({}, revenue_days_hash("not-json"))
  end

  # A opção do seletor precisa dizer a janela inteira: só o mês final obrigava o
  # usuário a deduzir que "agosto" significava junho, julho e agosto.
  test "rótulo da janela de 3 meses nomeia o intervalo, não só o mês final" do
    assert_equal "Junho a agosto de 2026", three_month_window_label(Date.new(2026, 8, 1))
  end

  test "janela que atravessa o ano mostra os dois anos" do
    assert_equal "Dezembro de 2025 a fevereiro de 2026", three_month_window_label(Date.new(2026, 2, 1))
  end
end
