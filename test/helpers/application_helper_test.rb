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

  # Base zero não vira mais um "—" mudo: o texto descreve o caso, e os dois casos
  # opostos (nasceu vendendo × segue zerado) deixam de dividir o mesmo símbolo.
  test "chip sem base comparável descreve: Novo quando vendeu" do
    html = variation_chip(0, 40)

    assert_includes html, "variation-chip--up"
    assert_includes html, ">Novo<"
    assert_includes html, 'data-tip="Primeira venda na base"'
  end

  test "chip sem base comparável descreve: Voltou a vender quando a ativação é antiga" do
    html = variation_chip(0, 40, novo: false)

    assert_includes html, "variation-chip--flat"
    assert_includes html, ">Voltou a vender<"
    assert_includes html, 'data-tip="Sem venda no mês anterior; ativação antiga"'
  end

  test "chip sem base comparável descreve: Sem venda quando segue zerado" do
    html = variation_chip(0, 0)

    assert_includes html, "variation-chip--flat"
    assert_includes html, ">Sem venda<"
    assert_includes html, 'data-tip="Zerado nos dois períodos"'
  end

  test "NET MDR trunca em duas casas, sem arredondar" do
    assert_equal "0,29%", net_mdr_label(0.299)
    assert_equal "0,30%", net_mdr_label(0.30)
    assert_equal "Inativo", net_mdr_label(nil, "Inativo")
    assert_nil net_mdr_label(nil)
  end

  test "equipamentos: lista os presentes, distingue nenhum de desconhecido" do
    assert_equal "Link pgto · POS", equipment_summary(true, 2, 0)
    assert_equal "POS", equipment_summary(false, 0, 3)
    assert_equal "Sem equipamentos", equipment_summary(false, 0, 0)
    assert_nil equipment_summary(nil, nil, nil)
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

  # O mês escolhido é o M0 e a janela avança a partir dele: quem credenciou em junho é
  # apurado em junho, julho e agosto.
  test "rótulo da janela parte do M0 e nomeia até onde vai" do
    assert_equal "Junho a agosto de 2026", three_month_window_label(Date.new(2026, 6, 1))
  end

  test "janela que atravessa o ano mostra os dois anos" do
    assert_equal "Dezembro de 2025 a fevereiro de 2026", three_month_window_label(Date.new(2025, 12, 1))
  end
end
