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

  # O card de métrica cortava o valor de milhões com reticências, porque cinco deles dividem
  # a largura da tela. Os centavos em corpo menor devolvem o espaço que faltava — sem que
  # nenhum algarismo suma, que é o ponto: é valor de apuração.
  test "valor do card separa os centavos, sem perder um dígito" do
    html = brl_metric(2_475_790.64)

    assert_includes html, %(<span class="metric-value__cents">,64</span>)
    # O texto visível continua idêntico ao do brl: a separação é só de corpo.
    assert_equal brl(2_475_790.64), Nokogiri::HTML.fragment(html).text
  end

  # A garantia que importa em toda faixa: o que se lê na tela é o que o brl formata. Um
  # helper de apresentação que altere o número é o pior defeito possível aqui.
  test "o valor lido do card é o mesmo do brl, em qualquer grandeza" do
    [ 0, 1000, 176_366.12, 2_475_790.64, 24_757_906.48, 247_579_064.8 ].each do |valor|
      assert_equal brl(valor), Nokogiri::HTML.fragment(brl_metric(valor)).text,
        "o card mudaria o valor de #{valor}"
    end
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

  # O paginador mostra a primeira, a última e uma vizinhança da atual. Cada bloco é contíguo;
  # entre blocos a tela escreve "…". Sem janela, 31 páginas viravam 31 botões.
  test "blocos de páginas: primeira, vizinhança da atual e última" do
    assert_equal [], pagination_page_groups(1, 1), "uma página só não tem paginador"
    assert_equal [ (1..7).to_a ], pagination_page_groups(3, 7), "até sete, todas cabem"
    assert_equal [ [ 1, 2, 3, 4, 5 ], [ 16 ] ], pagination_page_groups(3, 16)
    assert_equal [ [ 1 ], [ 6, 7, 8, 9, 10 ], [ 16 ] ], pagination_page_groups(8, 16)
    assert_equal [ [ 1 ], [ 12, 13, 14, 15, 16 ] ], pagination_page_groups(16, 16)
  end

  # Um "…" que esconde uma página só é pior que a própria página: o número ocupa o mesmo
  # espaço e leva a algum lugar.
  test "salto de uma página vira o número, não reticências" do
    assert_equal [ (1..8).to_a ], pagination_page_groups(4, 8)
  end

  test "página fora da faixa não quebra o paginador" do
    assert_equal pagination_page_groups(1, 16), pagination_page_groups(0, 16)
    assert_equal pagination_page_groups(16, 16), pagination_page_groups(99, 16)
  end

  test "NET MDR trunca em duas casas, sem arredondar" do
    assert_equal "0,29%", net_mdr_label(0.299)
    assert_equal "0,30%", net_mdr_label(0.30)
    assert_equal "Inativo", net_mdr_label(nil, "Inativo")
    assert_nil net_mdr_label(nil)
  end

  test "equipamentos: inventário com quantidades, distingue nenhum de desconhecido" do
    assert_equal "Link pgto · 2 POS",
      equipment_summary({ "has_payment_link" => true, "smart_pos_count" => 2, "other_pos_count" => 0 })
    assert_equal "3 POS", equipment_summary({ "has_payment_link" => false, "other_pos_count" => 3 })
    # Caso real do EC 92513747: só TEF acusava "Sem equipamentos".
    assert_equal "2 TEF", equipment_summary({ "has_payment_link" => false, "tef_count" => 2 })
    # Caso real do EC 92517343: "Outros terminais" sozinho não nomeia nada.
    assert_equal "Link pgto · 1 terminal",
      equipment_summary({ "has_payment_link" => true, "other_terminals_count" => 1 })
    assert_equal "1 PIN · +4 outros",
      equipment_summary({ "pin_count" => 1, "other_terminals_count" => 4 })
    assert_equal "Sem equipamentos",
      equipment_summary({ "has_payment_link" => false, "smart_pos_count" => 0, "tef_count" => 0 })
    assert_nil equipment_summary({})
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
