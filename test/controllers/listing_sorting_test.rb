require "test_helper"

# A ordenação por coluna de valor vale em toda listagem que mostra valor, não só na de
# subcanal. Aqui a tela é a de faturamento por subcanal, cuja listagem vem inteira da
# consulta em cache — a ordem é aplicada na leitura, nunca na chave do cache.
class ListingSortingTest < ActionDispatch::IntegrationTest
  setup do
    import_synthetic_workbook
    refresh_audit_views
  end

  test "faturamento por MIC abre ordenado pelo mês anterior cheio" do
    get reports_path

    assert_response :success
    assert_select "th[aria-sort=descending] a.sort-link", text: /Mês anterior cheio/
    assert_select ".sort-sentence", text: /Ordenado por Mês anterior cheio, do maior para o menor/
  end

  test "a coluna escolhida ordena e o link preserva o Master" do
    channel = Channel.first

    get reports_path(sort: "current_revenue", direction: "asc", channel_id: channel.uuid)

    assert_response :success
    assert_select "th[aria-sort=ascending] a.sort-link", text: /Mês atual/
    assert_select "a.sort-link[href*=?]", "channel_id=#{channel.uuid}"
    assert_select "a.sort-reset[href*=?]", "channel_id=#{channel.uuid}"

    ordem = css_select("tbody td.text-right.tabular-nums").each_slice(3).map { |cells| cells.last.text.strip }
    valores = ordem.map { |texto| texto.gsub(/[^\d,]/, "").tr(",", ".").to_d }
    assert_equal valores.sort, valores, "a coluna Mês atual precisa sair em ordem crescente"
  end

  # "Quem caiu mais?" é a pergunta desta tela, e a variação não é coluna da consulta: é a
  # razão entre o mês atual e a base comparável, calculada na leitura.
  test "a listagem de MICs ordena pela variação" do
    get reports_path(sort: "variation", direction: "asc")

    assert_response :success
    assert_select "th[aria-sort=ascending].variation-col a.sort-link", text: /Variação/
    assert_select ".sort-sentence", text: /Ordenado por Variação, do menor para o maior/

    variacoes = css_select("tbody .variation-chip__value").map do |chip|
      chip.text.strip.gsub(/[^\d,-]/, "").tr(",", ".").to_d
    end
    assert_operator variacoes.size, :>=, 2, "com menos de duas linhas a ordem passa por vacuidade"
    assert_equal variacoes.sort, variacoes, "a variação precisa sair em ordem crescente"
  end

  # A tela 3M ordena por mês da janela, por ECs credenciados e pelo prêmio; os links levam a
  # janela junto, senão ordenar recomeçaria a apuração noutro recorte.
  test "a tela 3M ordena por mês da janela e mantém o recorte" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path(from_date: "2026-06-01", to_date: "2026-08-01",
      sort: "m1", direction: "asc")

    assert_response :success
    assert_select ".earnings-card-bar__sort a.sort-link.is-sorted[aria-current=true]", text: /M1/
    assert_select "a.sort-link[href*=?]", "from_date=2026-06-01"
    assert_select ".sort-sentence", text: /Ordenado por M1, do menor para o maior/
  end

  # A tela do recorrente virou cards: o card é o subcanal e a série de meses vive dentro
  # dele. Isso resolve a ambiguidade que a tabela tinha — "ordenar por débito de qual mês?"
  # deixou de existir, porque o que se ordena é o ganho da janela inteira.
  test "o recorrente lista cards de MIC ordenados pelo ganho da janela" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get recurring_reports_path

    assert_response :success
    assert_select "article.earnings-card"
    assert_select "article.earnings-card .metric-label", text: /Ganho na janela/
    # O total da janela vive na primeira dobra, junto dos números do último mês fechado.
    assert_select "section.metric-grid .metric-card .metric-label", text: "Ganho na janela"
    assert_select "section.metric-grid .metric-hint", text: /Cada competência é apurada sozinha/
    assert_select ".sort-sentence", text: /Ordenado por Ganho na janela, do maior para o menor/
    # A série do subcanal continua dentro do card, em ordem cronológica.
    assert_select "article.earnings-card tbody th[scope=row]", minimum: 1
  end

  test "o recorrente aceita ordenar por nome do MIC" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get recurring_reports_path(sort: "name", direction: "asc")

    assert_response :success
    assert_select ".sort-sentence", text: /Ordenado por MIC, do menor para o maior/
    assert_select "a.sort-reset"
    # A ordem dos cards precisa ser a alfabética de verdade, não só o rótulo.
    nomes = css_select("article.earnings-card .earnings-card__name").map { |node| node.text.strip }
    assert_equal nomes.sort_by(&:downcase), nomes
  end
end
