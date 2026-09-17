# Layout da interface

Casca visual da aplicação, introduzida na branch `feature/cork-layout-sidebar-breadcrumbs`
sobre o padrão de admin "Cork". Este documento registra a estrutura, as decisões e o que a
revisão de frontend corrigiu, para que a próxima alteração parta do que existe e não do
que parece existir.

## Estrutura

```
┌──────────────────────────────────────────────────────────────────────┐
│ topbar (sticky, escura)                                              │
│ [marca]  ▾ Dashboard   ▾ Operação                          [☰] [⌘/] [sinal]  │
│          └ Faturamento  └ Estabelecimentos                                   │
│            Clover Capital     Importar arquivo                               │
│            Semanal            Metabase                                       │
│            Ganhos 3M                                                         │
│            Recorrente                                                        │
├──────────────────────────────────────────────────────────────────────┤
│ breadcrumb                                                           │
│ ┌──────────────────────────────────────────────────────────────────┐ │
│ │ page-hero / filter-panel / table-frame / metric-card             │ │
│ └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

| Peça | Arquivo | O que faz |
| --- | --- | --- |
| Topbar | `app/views/layouts/_navbar.html.erb` | Marca, menu horizontal em dois grupos (**Dashboard** e **Operação**), busca global e o sinal de arquivo |
| Busca global | `SearchController`, `GlobalSearch`, `app/views/search/index.html.erb`, `app_layout_controller.js` | Digita EC, CNPJ, nome, cidade, CNAE ou subcanal e vê subcanais e estabelecimentos ao vivo; `Ctrl+/` (`⌘/` no Mac) abre, `Esc` fecha, `Enter` abre o primeiro resultado |
| Breadcrumb | `ApplicationHelper#render_breadcrumbs` | `Início / <página>`; agrupamentos do menu não entram na trilha |
| Sinal de arquivo | `ApplicationHelper#header_file_status` | Há quanto tempo a carteira recebeu arquivo; vermelho a partir de `ImportBatch::STALE_AFTER_DAYS` |

### Breakpoints

| Largura | Comportamento |
| --- | --- |
| > 1400px | Uma linha: marca, menu, busca e sinal |
| ≤ 1400px | O menu desce inteiro para a segunda linha da barra |
| ≤ 1200px | A barra de filtros da tela de subcanal passa a duas colunas; a grade de cards do recorrente e do 3M passa a uma coluna |
| ≤ 900px | O menu sai da barra e vira lista vertical atrás do botão `.nav-toggle` (☰); a barra de filtros passa a uma coluna |
| ≤ 560px | Somem a legenda da marca e o atalho da busca (fica o ícone); o sinal encolhe |

Acima de 900px o menu nunca rola nem corta: quebra linha e a barra cresce o que precisar.
Abaixo disso ele colapsa no hambúrguer. A busca na barra é só ícone + atalho (o texto existe
para leitor de tela); o campo de verdade fica no diálogo.

### Ícones

Subconjunto do **Phosphor** (MIT) vendorizado em `vendor/icons/phosphor/` — os de peso regular
em `regular/`, inlined por `ApplicationHelper#icon`; os três de variação em peso duotone na raiz
da pasta, inlined por `#phosphor_icon`. Sem CDN e sem JavaScript. `icon_label(nome, texto)` monta ícone + texto para botões e links. O ícone é
decorativo (`aria-hidden`); quem dá o significado é o texto ao lado. Para acrescentar um:
baixe o SVG de `github.com/phosphor-icons/core/assets/regular/` para a pasta e use pelo nome.

| Onde | Ícones |
| --- | --- |
| Menu | chart-line-up, storefront (Clover Capital e Estabelecimentos), calendar-blank, calendar-check, chart-bar, upload-simple, caret-down (indicador de cada grupo), list-bullets (hambúrguer) |
| Ordenação | caret-up-down (coluna ordenável em repouso), caret-down e caret-up (sentido da coluna ativa) |
| Trilha | house em "Início" |
| Ações | download-simple, funnel, magnifying-glass, eraser, upload-simple, trash, arrow-counter-clockwise, arrow-left, arrow-square-out, x (fechar a busca) |
| Variação | trend-up, trend-down e minus, em peso **duotone**, por `ApplicationHelper#phosphor_icon` |
| Cards da importação | calendar-check, file-arrow-up, cpu |

### O selo do cabeçalho diz duas idades, não uma

O selo do topo, presente em toda página, mostra **dois sinais**: há quanto tempo o último
arquivo chegou e **até que dia o faturamento dele vai**. Cada um tem a própria bolinha, verde
ou vermelha pela mesma janela de 12 dias (`ImportBatch::STALE_AFTER_DAYS`).

**Antes ele mostrava só o upload, e isso enganava.** Em 16/09/2026 o selo dizia "Arquivo há 2
dias" em verde. Medido no banco naquele dia:

| Canal | Último arquivo | Dados até |
| --- | --- | --- |
| Ramos e Silva (10 MICs) | 11/09 | 09/09 |
| Região Goiás (2 MICs) | **14/09** | **26/08** |

Os 2 dias verdes eram do upload da Região Goiás — justamente o canal cujos dados param em
agosto. O selo usava o arquivo mais novo para dar o sinal mais tranquilizador sobre o canal
mais atrasado.

Três decisões:

- **O que o selo escreve é o pior de cada sinal**, nunca o mais recente (`FileFreshness`). É a
  mesma regra do corte de período em `ReportScope#cutoff_day`: o observado não superestima a
  cobertura.
- **O selo é geral e não nomeia master** (decisão do usuário, 16/09/2026). Um master defasado
  defasa a leitura da base inteira, porque as telas comparam os canais entre si — o alerta é
  da base, não de um nome. O selo segue sendo link para a tela de importação.
- **A quebra por master mora na tela de importação**, num painel que abre com a manchete
  ("1 master com dados desatualizados" ou "Todos os masters em dia") e lista os defasados
  primeiro, com a data dos dados e a idade do arquivo de cada um. É lá que a pergunta "quem
  está atrasado" é feita.
- **O badge do menu lateral usa a mesma instância** (`ApplicationController#file_freshness`),
  então a consulta roda uma vez por requisição e os dois números nunca divergem
  (`test/controllers/metabase_controller_test.rb` guarda isso).

Duas armadilhas que o serviço fixa em teste:

- **A data do arquivo sai no fuso do app.** O valor cru da consulta volta em UTC, e sem
  converter um arquivo recebido às 21h de ontem contava como de hoje — o selo dizia um dia a
  menos que a tela de importação.
- **Ausência não é sinal verde:** canal sem arquivo ou sem cobertura conta como atrasado.

### Busca ao vivo na lista de estabelecimentos

O formulário de busca mira o Turbo Frame `establishments` que envolve a listagem
(`data-turbo-frame`), com `data-turbo-action="advance"` para a URL acompanhar o filtro. O
controller Stimulus `live-form` submete 250ms depois da última tecla; o botão e o Enter
continuam funcionando sem JavaScript. É o mesmo mecanismo da busca global.

### Listagem: tabela ou card

Duas telas viraram grade de cards; as outras continuam tabela. A regra que separa as duas é
o que a linha carrega:

**Card quando a linha tem estrutura interna** — uma série ou uma matriz que não cabe numa
célula:

| Tela | Partial | O que a tabela fazia antes |
| --- | --- | --- |
| Recorrente (`/reports/recurring`) | `reports/_recurring_card.html.erb` | Uma linha por subcanal **e** mês — hoje 10 subcanais × 6 competências, 60 linhas —, e "ordenar por débito" não tinha resposta única |
| Ganhos 3M (`/reports/three_months`) | `reports/_three_month_card.html.erb` | Uma linha por subcanal, mas cada célula de mês guardava três números (total, e débito e crédito em subtexto) — uma matriz de 3×3 espremida em três células |

**Tabela quando cada célula é um número só e a comparação é entre linhas.** É o caso do
faturamento por subcanal (`/reports`): a leitura é varredura de coluna ("quem caiu mais?"),
e o `tfoot` põe cada total sob a sua coluna, o que deixa conferir que as partes fecham o
todo. Numa grade de cards não há onde pôr esse rodapé.

Anatomia do card, igual nos dois (`.earnings-card`):

1. cabeçalho com o nome do MIC, que leva ao nível seguinte;
2. bloco fechado com o número que a tela apura — ganho na janela, prêmio de entrada — e a
   composição dele logo abaixo (no 3M, pares rótulo/valor em `.earnings-card__parts`);
3. tabela com a série, dentro do card.

O card é o próprio scrollport da tabela que ele contém (`min-width: 0` no item da grade e
`overflow-x: auto` no `.table-scroll` de dentro). Sem isso a tabela larga esticava a coluna
da grade e vazava por cima do card vizinho — `test/system/layout_and_import_test.rb` compara
`scrollWidth` e `clientWidth` de cada card e falha se voltar a acontecer.

### Listagem do MIC: uma linha por cliente

Em `/reports/sub_channels/:id` a linha é o **cliente (CNPJ)**, e não o ponto de venda: o
faturamento de todos os ECs dele entra somado numa linha só (pedido do usuário, 10/09/2026).
Na carteira real isso leva 470 linhas a 302, e nenhum CNPJ aparece em dois MICs — medido —,
então agrupar dentro do subcanal é o mesmo que agrupar por CNPJ.

O que a linha mostra, e de onde o valor vem quando os ECs divergem:

| Coluna | Regra | Por quê |
| --- | --- | --- |
| **Net MDR** | só alíquota **positiva**; faixa (`0,42% a 2,52%`) quando os ECs divergem | dos 470 ECs, 253 chegam `Inativo`, 4 negativos e 2 zerados: nenhum afirma alíquota. 5 CNPJs têm dois positivos diferentes, num deles de 0,62% a 2,53% — escolher um esconderia 4× a diferença |
| Estabelecimento | CNPJ acima do nome; nome pelo valor mais frequente (`mode()`) | 3 CNPJs têm razão social divergente entre os ECs e 2, nome fantasia. `MAX` pegaria o maior alfabeticamente, não o mais provável |
| Status | **Ativo** se ao menos um EC estiver ativo | a suspensão é do cliente; 8 dos 9 CNPJs de status misto são troca de EC |
| Datas do ciclo | Cred. e Ativ. = a mais antiga; Susp. e Uso do app = a mais recente | o cliente entrou na primeira; um EC novo não rejuvenesce o credenciamento |
| Melhor conversa | **todas**, uma por EC, rotuladas pelo EC no modal | 116 dos 302 clientes têm mais de um texto diferente |

A coluna do número do EC **deixou de existir** na tela — o inventário de equipamentos saiu
com ela, porque é de cada ponto de venda. Os dois continuam na ficha do cliente
(`/establishments/:id`), onde a unidade é o EC.

**O filtro escolhe o cliente; a soma é sempre dos ECs todos.** Isso não é detalhe de
implementação: todo filtro desta tela nasceu por EC, e se um deles voltar para o `WHERE`
antes do `GROUP BY`, o cliente com três ECs em que só um casa aparece com a soma de **um** —
faturamento errado e calado, numa tela de auditoria. Em `EstablishmentListingQuery` os
filtros vivem no `HAVING`, e `test/services/establishment_listing_query_test.rb` trava a
invariante: buscar o número de um EC devolve o cliente com os dois ECs somados.

Status e data comparam o **valor agregado** — o mesmo que a linha mostra —, para que quem
filtra "suspensos" nunca receba uma linha escrita "Ativo". A busca é a exceção e mede EC por
EC: quem digita o número de um EC está procurando o cliente dono dele, e esse número não está
mais na tela para ser comparado como agregado.

Duas armadilhas que esta mudança pagou:

- **`pluralize(2, "estabelecimento")` devolve `"2 estabelecimento"`.** O pt-BR não declara
  inflexões, então sem o plural explícito nada é pluralizado. Todo `pluralize` de texto em
  português precisa dos dois argumentos.
- **A exportação acompanha a tela.** `EstablishmentListingExporter::HEADERS` trocou `EC` por
  `Net MDR`, como texto e não número, porque o cliente com alíquotas divergentes leva a faixa.

### A barra de filtros da listagem do MIC

Barra em **pílulas** (15/09/2026). Cada filtro é um controle só, com o rótulo dentro e o valor
à vista: `( Status  Ativo × ⌄ )`, `( Faturamento  mês atual até R$ 12.000,00 ⌄ )`. O que veio
antes, e por que saiu:

| Antes | Problema |
| --- | --- |
| Cinco rótulos em caixa-alta laranja sobre os controles | competiam com o título da seção e repetiam o que o valor já dizia |
| Cinco aparências de controle | caixa com chip, botão com ícone, select, alça crua e campo de texto, lado a lado |
| Linha de chips com o recorte ativo | repetia o estado que os próprios controles mostram |
| Grade de colunas de largura fixa | obrigava a inventar um valor de `rem` por campo, e quebrou duas vezes quando um campo novo entrou |

O que a barra é agora:

- **Uma forma só**: `.filter-pill__trigger`, 2,5rem de altura, borda e raio iguais. O rótulo
  (`.filter-pill__label`) é miúdo e sem cor; o valor (`.filter-pill__value`) é o que tem peso,
  e fica apagado quando não há escolha ("todos", "todas", "qualquer").
- **Fileira que quebra sozinha** (`display: flex; flex-wrap: wrap`), no lugar da grade: cada
  pílula tem a largura do próprio conteúdo, e nenhum campo novo pede recálculo de colunas.
- **O faturamento é pílula com painel** (`revenue_filter_controller.js`): o gatilho resume o
  recorte e o painel guarda a competência e as duas alças. Era o único controle com dois campos à
  mostra, e era ele que obrigava a barra a ter duas alturas.
- **A caixa do menu acompanha o texto, não o gatilho.** Com `right: 0` ela tinha a largura
  da pílula — 122px na pílula "Data" — e "Credenciamento" saía 49px para fora dela (medido,
  relatado com print em 16/09/2026). Agora é `min-width: 100%` com `width: max-content`.
- **O valor marcado é texto, não caixinha** (`.filter-pill__tag`): caixa com borda dentro de
  caixa com borda vira ruído. O `×` de cada valor continua, com alvo de toque de 44px.
- **"Limpar" só existe quando há o que limpar.** Botão permanente para desfazer o nada é ruído.

O seletor de intervalo (`reports/_date_range_picker`) ganhou a variante `pill: true`, usada só
aqui; as telas 3M seguem com o rótulo em cima, como o resto da barra delas.

### Filtro por faixa de faturamento

Na barra de filtros da listagem do MIC, um **dropdown de base** e um **slider de duas alças**
formam o filtro de faturamento. A escala vai de 0 a R$ 300.000,00 em paradas de passo
crescente (`EstablishmentListingQuery::REVENUE_STOPS` — ver adiante); o dropdown diz a que
competência a faixa se aplica (`REVENUE_BASES`):

| Base | O que filtra |
| --- | --- |
| **Todas** (padrão) | nada — é o estado desligado |
| **Mês atual** | `piso ≤ mês atual ≤ teto` |
| **Mês anterior cheio** | `piso ≤ mês anterior cheio ≤ teto` |

**Quem liga e desliga o filtro é a base, não o valor** (decisão do usuário, 15/09/2026). Antes
o desligado era implícito — o topo da escala significava "sem teto", porque um
`input[type=range]` sempre envia valor. Com o dropdown o desligado ficou explícito, o topo da
escala voltou a significar R$ 300.000,00 e nada mais, e as alças ficam apagadas enquanto a
base está em "Todas".

Cinco decisões, cada uma com um porquê:

- **Zero é escolha, e não ausência dela.** Teto zero responde "quem não faturou nada", que é
  uma pergunta legítima desta tela; por isso a ausência se testa por `blank?`, e não por
  "menor ou igual a zero". Na carteira real, com base no mês atual: teto de R$ 12.000 devolve
  26 dos 35 clientes; teto zero devolve 7.
- **Por que a base é escolha da tela, e não decisão do código — medido:** enquanto o mês atual
  é parcial, ele é quase sempre o menor dos dois. Na carteira inteira, só 22 dos 406 clientes
  já faturaram no mês em curso mais do que no mês fechado inteiro. Com teto de R$ 12.000 num
  MIC de 35 clientes, "mês atual" devolve 26 e "mês anterior cheio" devolve 9: são perguntas
  diferentes.
- **A faixa inclui as duas pontas.** A contagem anterior era estritamente abaixo; com o
  slider, "de R$ 1.000 até R$ 5.000" lê como ≥ e ≤, e a dica da tela escreve isso.
- **O piso em zero não corta.** É o fundo da escala, e "de R$ 0,00" quer dizer "sem piso". Um
  `>= 0` literal tiraria da lista quem fechasse o mês negativo por estorno — a base real tem um
  lançamento de −R$ 15.891,74, e nenhum cliente fecha o mês no negativo hoje, mas pode.
- **O filtro mora no `HAVING`**, como os outros desta tela: no `WHERE` antes do `GROUP BY`, o
  cliente com três ECs em que só um cabe no teto apareceria com a soma de um — faturamento
  errado e calado.

O bloco ao lado do título mostra a faixa por extenso e as duas contagens (mês anterior cheio e
mês atual). Elas são independentes — o mesmo cliente costuma estar nas duas — e por isso nunca
são somadas. Com o filtro ligado, a contagem da competência escolhida coincide com a da tabela,
porque é por ela que o recorte acontece; quem informa aí é a outra.

**O bloco conta a faixa, e não só o teto** (decisão do usuário, 15/09/2026). Medido no MIC
GOIANIA 4: com teto de R$ 50.000 no mês atual são 137 clientes, e com piso de R$ 10.000 junto
são 21 — se o bloco ignorasse o piso, estamparia 137 ao lado de uma tabela de 21 linhas.

**As duas pontas que o bloco anuncia vêm da consulta** (`low_revenue_counts[:floor]` e
`[:ceiling]`), e não são recalculadas na tela: elas divergiram uma vez — com o filtro desligado
e um teto na URL, o bloco anunciava R$ 12.000 enquanto as contagens usavam a referência.

**Com o filtro desligado o bloco conta pela referência, e não pelo topo da escala**
(`LOW_REVENUE_REFERENCE`, R$ 30.000,00): com a escala em R$ 300 mil, "abaixo do topo" devolve a
carteira inteira — 35 de 35, medido —, que é verdade e não informa nada. R$ 30 mil é o corte que
o usuário pediu em 14/09/2026, e é o que a tela mostra enquanto ninguém escolhe faixa.

**Duas alças são dois `input[type=range]` empilhados** — não existe range de duas alças em
HTML, e nenhum navegador implementa. Os dois ficam no mesmo lugar (`position: absolute`), o
input inteiro é transparente ao clique (`pointer-events: none`) e só a alça o recebe de volta
(`::-webkit-slider-thumb` e `::-moz-range-thumb`); sem isso o input de cima cobriria a alça do
de baixo. O trilho e a faixa acesa são pintados à parte porque os trilhos nativos ficam
transparentes: empilhados, apareceriam como duas linhas.

**A escala não é linear, e é essa a razão de ela caber.** O passo cresce com o valor —
R$ 1.000 até 30 mil, R$ 10.000 até 100 mil, R$ 50.000 até 300 mil (`REVENUE_STOPS`, 42
paradas). A razão é medida: 171 dos 186 clientes com faturamento no mês atual ficam até
R$ 30.000 e **nenhum** passa de R$ 300.000; no mês anterior cheio são 200 de 263 abaixo de
30 mil e 4 acima do topo. Com passo fixo de R$ 1.000 a faixa que esta tela audita ocupava
**10% do trilho** — 23px, menos que as duas alças de 16px somadas, então elas se encavalavam
e a faixa acesa entre as duas sumia. Com as paradas espaçadas ela ocupa **74%**.

Três consequências de desenho, todas deliberadas:

- **A alça carrega o índice da parada, não o valor.** Quem viaja no formulário é um campo
  escondido em reais, e por isso a URL e o contrato com o servidor não mudaram. O preço:
  sem JavaScript a alça deixa de mexer no valor — o campo escondido fica com o que o
  servidor desenhou.
- **As marcas ficam na posição real da parada.** Igualmente espaçadas elas mentiriam:
  R$ 30.000 fica a 73% do trilho, não a 25%.
- **A faixa acesa acompanha a posição, não o valor.** É o índice que diz onde a alça está.

**O painel tem a largura do gatilho** (pedido do usuário, 16/09/2026), e a pílula tem largura
fixa de 28rem em vez de acompanhar o texto: o resumo muda de comprimento enquanto a alça
anda, e o painel aberto ficaria mudando de largura junto. De quebra, o trilho passou de 273px
para 417px.

Duas armadilhas do empilhamento, ambas no `revenue_filter_controller.js`:

- **As alças não se atravessam**: a que o usuário move para no valor da outra.
- **Juntas no mesmo ponto, uma cobre a outra**, e a de cima tem que ser a que ainda tem para
  onde ir — no topo da escala é o piso, porque o teto já não sobe. Sem essa troca de
  `z-index` o controle trava no fim da escala.

Sem JavaScript as alças continuam funcionando: são campos comuns e o formulário os envia igual
— o que o Stimulus faz é mostrar o valor e desenhar a faixa antes de o filtro ser aplicado, no
mesmo formato do `brl` do servidor. No gatilho o resumo vai compacto (`revenue_summary`): sem
centavos, que com passo de R$ 1.000 são sempre zero, e com um traço no lugar do segundo "R$" —
por extenso são 396px de texto para uma caixa de 301px, e o teto sumia nas reticências.

### Paginação

`app/views/shared/_pagination.html.erb`. A barra leva **Anterior, os números e Próxima**: até
sete páginas todas aparecem; acima disso vale uma janela — a primeira, cinco em volta da atual
e a última, com `…` nos saltos. Um salto de **uma** página vira o próprio número, que ocupa o
mesmo espaço e leva a algum lugar. O "Página X de Y" saiu: a atual está em laranja cheio e a
última é sempre o número do fim.

Cada bloco contíguo é um `join` — o mesmo grupo de escolha do "Por página" logo acima. Isso não
é estética: `.btn` solto herda o laranja cheio da regra do sistema, e as páginas ficariam todas
iguais, sem mostrar qual é a atual. Quem calcula a janela é `pagination_page_groups`; o caminho
de cada página vem de quem renderiza, num lambda, porque cada tela tem o seu recorte na URL.

A listagem de `/establishments` ainda usa a barra antiga, só com Anterior e Próxima.

### O menu de ações não pode ser recortado pela tabela

O painel do menu (`.actions-menu__list`) abre para fora da linha, e `.table-scroll` o cortava:
ele tem `overflow-x: auto` para a tabela rolar na horizontal, e **overflow declarado num eixo
torna o outro `auto` também** — não existe pedir só o horizontal. Medido no menu da última
linha da carteira real: dos 100px do painel, 57 ficavam fora, e o resto aparecia por baixo da
barra de paginação.

Nenhuma solução de CSS resolve: `absolute` é recortado por qualquer ancestral com overflow, e
abrir sempre para cima só troca o problema de lugar — na primeira linha da tabela o painel
sairia pelo topo. Por isso `actions_menu_controller.js` troca o painel para
**`position: fixed`** ao abrir e calcula a posição a partir do gatilho, refazendo a conta a
cada rolagem e a cada `resize`. Ele abre para baixo e **inverte para cima só quando o painel
não cabe até o fim da janela** — conta que depende da altura medida na hora, que o CSS não
tem. Sem JavaScript o painel continua `absolute` — recortado, como era, e não quebrado.

Três escolhas que já custaram medição:

- **Ancorar pela direita, não pela esquerda.** Com `left`, a caixa `fixed` encolhe para caber
  no que resta até a borda e sai do alinhamento — 11px fora, medido.
- **`documentElement.clientWidth`, não `window.innerWidth`.** O bloco que contém um elemento
  `fixed` exclui a barra de rolagem; `innerWidth` a inclui.
- **Duas inscrições de `scroll`, com e sem `capture`.** Quem rola é o `.table-scroll`, e
  rolagem de elemento não borbulha — daí a captura. Com **só** a de captura, medido: rolar a
  tabela reposicionava o painel e rolar a página o deixava para trás.

### Ordenação das listagens

A regra vive em `ListingSort`, num lugar só. A coluna e o sentido vêm da URL e são validados
contra a **lista fechada** de cada tela: na listagem paginada o nome da coluna vira SQL, e em
qualquer tela coluna inexistente cai no padrão em vez de quebrar a página. O primeiro clique
traz o maior valor no topo — é o que se procura numa auditoria; o clique seguinte inverte.

O mecanismo **não** é escondido atrás de abstração, porque os dois casos são diferentes de
verdade: quem tem paginação ordena no banco (`sql_order_by`), senão ordenaria só a página
visível; quem já traz o array inteiro na memória ordena em Ruby (`sort_rows`).

| Tela | Colunas ordenáveis | Padrão |
| --- | --- | --- |
| Faturamento (`/reports`) | mês anterior cheio, base comparável, mês atual, variação | mês anterior cheio |
| Estabelecimentos do subcanal | mês anterior cheio, base comparável, mês atual | mês anterior cheio (no banco, com desempate) |
| Recorrente | ganho na janela, último mês fechado, MIC | ganho na janela |
| Ganhos 3M | prêmio de entrada, ECs no M0, M0, M1, M2 | prêmio de entrada |

Linha **sem valor** vai para o fim nos dois sentidos, como o `NULLS LAST` do SQL: a variação
de um subcanal sem base comparável não é um percentual, e tratá-la como zero a colocaria
entre quem caiu e quem cresceu.

Três partials, conforme onde o link mora:

| Partial | Onde |
| --- | --- |
| `shared/_sortable_header` | cabeçalho de tabela; o link ocupa a célula inteira, dica incluída |
| `shared/_sort_links` | barra acima da grade, nas telas de card, onde não há cabeçalho para clicar |
| `shared/_sort_status` | a frase "Ordenado por…" e o link de volta à ordem padrão |

### Calendário do ritmo

A tela `/reports/weekly` mostra a competência escolhida como calendário: uma linha por semana
começando no **domingo**, cada dia sob o seu dia da semana, com faturamento e ECs na célula e
o total da semana ao fim da linha.

A troca não foi estética. A tabela anterior agrupava em faixas de sete dias a partir do dia 1,
e isso embaralha os dias da semana: medido em agosto de 2026, **sábado fatura 78% mais que
domingo** (R$ 318.584 contra R$ 179.024 de média diária). Uma faixa com dois sábados vale
~320 mil a mais que outra com um só — 20% de uma semana —, e a tela apresentava essa diferença
de calendário como diferença de desempenho. No calendário o mix de dias é o que se lê.

Três estados de célula, e é neles que mora a honestidade da tela (`RevenueCalendar`):

| Estado | Quando | Como aparece |
| --- | --- | --- |
| fora | dia de outra competência, nas bordas da grade | célula vazia |
| sem dado | dia além do corte do arquivo | travessão, apagado |
| coberto | dia que o arquivo cobre | valor, zero inclusive |

Sem essa distinção o mês corrente — coberto só até o dia de corte — mostraria dezenas de
células afirmando R$ 0,00. A intensidade da cor sai de `ApplicationHelper#calendar_heat`, em
cinco faixas do laranja da marca (tokens `--cork-heat-1..5`), normalizadas pelo maior dia do
próprio mês; dia zerado não recebe cor, porque ausência de venda não é um tom.

O total da semana conta **ECs distintos**, nunca a soma dos dias: o mesmo EC vende em vários
dias da mesma semana. E a âncora do mês anterior segue a regra de alinhamento da casa — mês
escolhido parcial compara com o anterior até o mesmo dia; competência anterior não importada
declara a lacuna em vez de mostrar zero.

### Clover Capital: o MIC é filtro, não coluna

A tela tinha uma coluna MIC repetindo o mesmo nome em toda linha e empurrando a tabela na
horizontal. Desde 10/09/2026 ela é um **select** acima da tabela, que abre em "Todas"
(`reports/stalled.html.erb`, `PreapprovedOffers#sub_channel_options`). O nome do MIC não
sumiu da linha: ficou **dentro da célula do estabelecimento**, abaixo da contagem de ECs e
sem destaque — mesma classe discreta da linha de ECs. Medido nas duas formas, com a janela em
1440px e a carteira real: como coluna, a tabela pedia 1614px num espaço de 1376px (238px de
rolagem horizontal); como linha da célula, pede 1376px e a rolagem some.

Três decisões, cada uma com um porquê:

- **O select só oferece MIC que tem cliente com oferta.** Na carteira real são 15 clientes
  espalhados por 6 MICs (medido em 10/09/2026); oferecer os outros seria oferecer tabela vazia.
  A lista também não se recorta pelo MIC escolhido — senão escolher um faria os demais sumirem
  da própria lista, e não haveria como voltar.
- **O filtro vive no `HAVING`**, como na listagem do MIC e pela mesma razão: no `WHERE`, o
  cliente com ECs em mais de um MIC apareceria com a contagem de ECs e a checagem de
  divergência recortadas pelo filtro. Hoje nenhum dos 15 tem ECs em dois MICs (medido), mas a
  consulta não depende disso ser verdade amanhã — e há teste para o caso.
- **MIC inexistente é 404, não tabela vazia**, e MIC de outro Master que o escolhido também: a
  mesma regra que o canal já seguia.

O canal escolhido viaja num campo oculto do formulário, senão aplicar o MIC derrubaria o
recorte de Master de quem chegou por ele.

**A tela exporta CSV e XLSX** (`PreapprovedOffersExporter`). A anotação fica de fora do
arquivo: é texto livre com anexos, e célula de planilha não é onde se lê isso. No total só
entram volume e contagem de ECs — somar prazo ou taxa de clientes diferentes não descreve
oferta nenhuma, e a média tampouco.

### As telas do modelo de remuneração

O **Anexo C** da Circular de Oferta de Franquia mudou o que as duas telas mostram.

- **Ganhos 3M: o intervalo virou exceção.** O adicional por faturamento tinha duas colunas na
  tela ("entre R$ X e R$ Y") porque a modalidade de antecipação não era classificável. O
  contrato mostrou que a coluna sai da **modalidade contratada** (`SOLUÇÕES FINANCEIRAS`), e
  a tela passa a mostrar um valor. O intervalo sobrevive só para o EC cuja origem não declara
  a modalidade, e o card diz quantos são.
- **O card do EC mostra as parcelas por mês** quando mais de uma tem valor — "por mês: M0
  R$ 250,00 · M1 R$ 300,00". É a apuração sequencial do contrato, e é ela que alimenta a base
  do redutor na tela do recorrente.
- **O recorrente ganhou a coluna "Credenciamento"**, e a última coluna virou "Participação do
  mês". A parcela aparece porque **entra na base do ajuste**: sem mostrá-la, o redutor não
  seria conferível a partir do que a linha exibe. É o mesmo dinheiro da tela 3M — ali por
  safra do EC, aqui por competência de calendário.
- **Competência aberta não mostra ajuste.** Um mês pela metade parece queda por não ter
  terminado; o redutor incidiria sobre dado incompleto.
- **A tela do recorrente declara o que o extrato paga e o portal não apura** — antecipação,
  Pix, MDR Flex e Clover Capital —, com a fórmula do extrato e o insumo que falta no arquivo.
  Omitir daria a entender que o número na tela é o fator inteiro.
- **O recorrente marca a origem do Net MDR**: sem marca é o realizado, que chega no arquivo
  do mês seguinte; ‡ quando o mês ainda usa o próprio arquivo (provisório); † quando usa o
  mais antigo disponível. O `title` diz o porquê, e o CSV escreve a origem em texto.
- **O card do EC diz em que mês a campanha APP caiu** ("app em ago/2026"), porque desde o
  extrato ela é paga no mês do primeiro acesso, não em M0.

**Indicadores do Anexo B** (`/reports/indicators`) usa a mesma anatomia de card do
recorrente: o MIC nomeia o card, o bloco do topo é o retrato (quantos indicadores estão em
Risco no último mês fechado, e quais) e a série de competências fica na tabela interna, em
ordem cronológica — é ela que dá sentido à contagem de meses seguidos em Risco.

- **Valor e leitura na mesma célula.** O percentual em cima e a palavra (Adequado, Atenção,
  Risco) embaixo, em cor; a fração por trás do percentual ("9 de 35 · 2 pendentes") fica no
  `title`, para a conta ser conferível sem alargar a tabela de seis colunas.
- **Célula sem leitura é travessão, e o `title` diz por quê** — "Sem Mapa importado desta
  competência" ou "Nenhuma proposta com data neste mês". Zero seria uma afirmação.
- **Competência aberta mostra o valor sem a palavra**, com "parcial" sob o mês, como no
  recorrente.
- **O alerta dos 60 dias só aparece quando alcança**: dois meses fechados seguidos em
  Risco, citando a cláusula 12.2 (xx). É a única linha em vermelho fora das células.
- **A ordem padrão traz o risco ao topo** — "Indicadores em risco", do maior para o menor;
  a alternativa é o nome do MIC.
- **A tela declara as duas leituras que o anexo obriga** (a base do mês e a inversão de
  "Atividade") e os dois indicadores que não apura, no mesmo `metric-hint` que o recorrente
  usa para a antecipação. Ver `README.md`, "Indicadores do Anexo B".

### Exportações

**Toda tela de relatório exporta CSV e XLSX, menos duas.** `TabularExporter` faz a mecânica —
CSV e planilha a partir das mesmas linhas — e cada tela declara só colunas, nome da aba e a
nota do cabeçalho. Um exportador por tela, nenhum herdando de outro: o que elas compartilham
é a mecânica, não o formato.

| Tela | Exportador | A linha do arquivo |
| --- | --- | --- |
| Listagem do MIC | `EstablishmentListingExporter` | cliente |
| Clover Capital | `PreapprovedOffersExporter` | cliente |
| `/establishments` | `EstablishmentsExporter` | cliente, com os ECs numa célula |
| Ritmo do mês | `WeeklyRevenueExporter` | dia coberto pelo arquivo |
| Modal do dia | `DayCompaniesExporter` | cliente que vendeu naquele dia |
| Recorrente | `RecurringEarningsExporter` | MIC × competência |
| Ganhos 3M | `ThreeMonthEarningsExporter` | MIC, com o adicional resolvido pela modalidade, a contagem de ECs sem modalidade e as duas hipóteses no fim para conferência; M0/M1/M2 em colunas |
| Ganhos 3M de um MIC | `ThreeMonthEstablishmentsExporter` | EC, com modalidade, adicional resolvido e a parcela de cada mês (M0/M1/M2); as duas hipóteses no fim |

Quatro regras valem para todos:

- **O arquivo é do recorte da tela, não da página.** Os parâmetros da tela viajam no link do
  botão, e a paginação fica de fora: exportar só a página entregaria um recorte que ninguém
  pediu. Em `/establishments` isso é asserção de teste — a contagem do arquivo tem que bater
  com a da tela, não com a da página.
- **O nome do arquivo carrega o recorte** (`ganhos-3m-mic-gama.xlsx`, `ritmo-2026-08.csv`),
  senão dois downloads seguidos chegam com o mesmo nome na pasta.
- **Ausência de dado sai vazia, nunca zerada.** Mês sem cobertura no 3M, ajuste inexistente no
  recorrente, dia além da cobertura no ritmo: zero seria uma afirmação, e no Excel entra na
  média. É a mesma distinção que as telas fazem com o travessão.
- **O total só soma o que é somável.** A contagem de ECs distintos do ritmo fica em branco —
  somar ECs por dia contaria o mesmo EC uma vez por dia —, e prazo e taxa do Clover Capital
  também.

**A auditoria de faturamento (`/reports`) é a exceção**: exportava e deixou de exportar em
10/09/2026, a pedido do usuário. Saíram os botões, o endpoint e o `ReportsExporter` — botão
escondido com a rota de pé é meia remoção, e `/reports.csv` responde 406. **Os Indicadores
do Anexo B** nasceram sem exportação em 17/09/2026: a tela é leitura, e ninguém pediu o
arquivo ainda.

O link do **modal do dia** leva `data-turbo="false"`: ele vive dentro de um turbo_frame, e sem
isso o Turbo tentaria encaixar o arquivo no frame em vez de baixá-lo.

### Anotação do cliente

A mesma célula nas duas telas (`shared/_company_note_cell`, `shared/_company_note_modal`), em
lugares diferentes: no Clover Capital é a coluna "Anotação"; na listagem do MIC é um item do
**menu de ações**, porque ali as colunas não sobram. Um diálogo por tabela, nunca por linha.

A célula leva **só o botão**. O trecho do texto salvo já apareceu ali embaixo, no Clover
Capital, e saiu a pedido do usuário (10/09/2026): a linha cresce com o tamanho da anotação, e
uma anotação longa esticava a coluna até a tabela precisar rolar na horizontal. O texto vive no
modal, que é onde se lê e se escreve; na célula fica o ponto, que diz que existe.

A anotação é do **CNPJ**, não do EC, e quem diz isso é o cabeçalho do modal ("vale para os
3 ECs deste cliente"): toda tela que a edita mostra um cliente por linha e nenhuma lista os
ECs, então o alcance da nota precisa estar escrito em algum lugar.

Salvar não recarrega a tela: um `turbo_stream` troca a célula daquele cliente. O alvo é o id
que `company_note_cell_id` monta da uuid do cliente, e o helper existe porque duas pontas
precisam da mesma string — a partial escreve o id, o controller o endereça. Enquanto a listagem
do MIC era por EC, o mesmo cliente ocupava várias células e o alvo era um `replace_all` por
seletor; com uma linha por CNPJ, o id único basta.

A volta de cada tela é montada por route helper, a partir de uma lista fechada de origens
(`sub_channel`, `establishment`, `establishments`, e o Clover Capital como padrão). Caminho que
venha na requisição nunca é seguido: seria redirecionamento aberto, e o projeto entrega com o
brakeman limpo.

A tabela se liga pelo CNPJ e não por FK — ver o porquê no `CLAUDE.md`.

Diferente dos outros modais da casa, o conteúdo **chega por Turbo Frame** em vez de vir num
`data-*` do botão: é HTML com anexos, e vinte linhas de tabela carregariam vinte cópias. O
formulário escapa para `_top` no submit — dentro do frame, o Turbo procuraria o frame na
resposta do redirect e engoliria o flash — e fecha o diálogo no submit, porque o layout usa
`turbo_refreshes_with method: :morph`.

O botão **nunca vem `disabled`**, ao contrário do da melhor conversa: lá "não tem" é fato da
planilha; aqui é o convite para escrever. O rótulo é sempre "Anotar" — quem avisa que já há
conteúdo é o ponto (`.note-trigger__dot`), e o botão sai de `btn-outline` para o laranja cheio.

Editor é o Trix (Action Text), vendorizado em `vendor/javascript/trix.js` — o CSP tem
`script_src 'self'` e não aceitaria CDN. Anexo sai em tamanho original, com a largura contida
pelo CSS: o processador de variantes está desligado no projeto, e pedir variante devolveria o
arquivo cheio em silêncio.

### A mensagem de falha do import

Na tabela de lotes (`/import_batches`), a linha que falhou traz a mensagem sob o badge. Ela é
**diagnóstico de relance** e vive limitada (`.import-error`: duas linhas e 20rem): sem limite,
ela esticava a coluna de Status e empurrava o botão "Descartar" para fora da área visível —
medido na carteira real, janela de 1600px, com a tabela pedindo 2947px num espaço de 1502px,
1445px além, e a coluna de Status sozinha com 1698px.

O texto inteiro não se perde: está no `title` ao passar o mouse, no bloco `failure-report` do
topo da tela (para o último lote) e na ficha do lote, para onde o nome do arquivo já leva.

### Modal de lançamentos diários

Clicar na linha do cliente, na tela de subcanal, abre `.daily-modal` por Turbo Frame
(`reports/_daily_revenues.html.erb`). Ele mostra **três competências** lado a lado —
penúltimo mês, último e atual —, um dia por linha, com o cabeçalho da tabela colado no topo
ao rolar (o scrollport é a própria tabela, não a página).

**Esse cabeçalho já esteve parado e voltou a rolar duas vezes, por duas causas somadas**
(corrigidas em 14/09/2026, medidas no navegador contra a página servida):

- **O `turbo_frame` quebrava a cadeia do flex.** `.daily-modal__body` é a coluna e
  `.daily-modal .table-scroll` pede `flex: 1; min-height: 0; overflow: auto` — mas entre os
  dois entrou o elemento `turbo-frame`, que não é flex container nem item flexível. Quem
  crescia era ele, e quem rolava passou a ser o `<dialog>` inteiro: medido, diálogo com 664px
  de janela para 1656px de conteúdo e a tabela sem rolagem nenhuma. A regra que conserta é
  `.daily-modal__body > turbo-frame { display: flex; flex: 1 1 auto; min-height: 0 }`.
- **A moldura da listagem alcançava o `thead` do modal.** Os diálogos vivem dentro do mesmo
  `.table-frame` da tabela, e `.table-frame[data-controller~="sticky-table"] thead th` declara
  `position: static` — empatava em especificidade com a regra do modal e vencia por vir depois
  no arquivo. As duas regras de `position: static` passaram a usar `> .table-scroll`: elas são
  do cabeçalho **daquela** tabela, não de qualquer `thead` dentro da seção.

A mesma correção vale para o modal de **clientes do dia** (`/reports/weekly`), que tem a mesma
estrutura e sofria do mesmo problema.

O modal é do **cliente**, e soma os mesmos ECs que a linha soma: a rota é
`reports/sub_channels/:id/daily/:company_id`, com a uuid da empresa — nunca o CNPJ, que o
filtro de log esconde dos parâmetros mas não do caminho da URL. Quando a soma tem mais de um
EC, o cabeçalho escreve quantos; sem isso, quem confere o dia a dia contra a planilha não
sabe se está vendo um ponto de venda ou a soma de três.

Três regras que o modal segue de propósito:

- **Mês inteiro, não a faixa de dias dos filtros.** O modal é a leitura do lançamento, não o
  recorte da comparação.
- **Dia sem venda aparece zerado**, nunca sumido: é justamente o buraco que se abre o modal
  para ver. Já o dia que não existe na competência mostra travessão — 31 de setembro não é
  "sem venda".
- **A terceira coluna é condicional.** A planilha traz duas competências; a mais antiga só
  existe se importações anteriores a cobriram. Ela aparece quando está em `period_coverages`
  — coluna zerada diria "sem venda" onde a verdade é "sem dado".

### Vocabulário da tela

A interface chama **Master** o que o banco chama `channel`, e **MIC** o que ele chama
`sub_channel`. Não é apelido inventado: é o que os próprios dados dizem — o canal da carteira
se chama `MASTER FRANQUEADO ...` e os dez subcanais começam com `MIC`.

A fronteira que mantém o import intacto não é de camada, é de **referente**:

| A frase aponta | Palavra | Onde |
| --- | --- | --- |
| A coluna da planilha | `CANAL`, `SUB-CANAL` | `EXPECTED_HEADERS`, mensagens do import, o nome `SEM CANAL` gravado no banco |
| A entidade no código | `channel`, `sub_channel` | tabelas, models, parâmetros de URL |
| O que o usuário lê | **Master**, **MIC** | rótulos, títulos, filtros, contagens, exportação |

O importador lê células pelo nome do cabeçalho e escreve linhas; ele nunca lê rótulo de tela.
Por isso a terceira faixa muda sozinha. E a mensagem "confira o CANAL da planilha" **não**
muda: ela manda o analista a uma coluna que se chama assim no arquivo — traduzi-la a tornaria
falsa.

O canal fictício é o único ponto onde as duas se encontram: no banco ele continua `SEM CANAL`
(é o que o analista procura no arquivo), e `ApplicationHelper#channel_name` o exibe como
`SEM MASTER`. `test/controllers/vocabulary_test.rb` abre as dez telas e falha se alguma voltar
a escrever a palavra antiga — foi ele que achou as duas dicas de busca esquecidas nesta troca.

### Tokens

Definidos em `app/assets/tailwind/application.css` dentro de `[data-theme="bin"]`. Os tons
`--cork-*` são derivados por `color-mix` das cores do tema daisyUI, então trocar a cor
primária do tema propaga para a casca inteira:

| Token | Uso |
| --- | --- |
| `--cork-primary-100` / `-200` | Hover das abas de variação e do resultado de busca; seleção de texto |
| `--cork-success-100`, `--cork-danger-100`, `--cork-warning-100` | Fundos das badges e do sinal de arquivo |
| `--cork-dark-100` | Fundo da `.badge-ghost` |
| `--cork-muted` / `--cork-strong` | Texto secundário / texto de destaque |
| `--cork-shadow` | Sombra única dos cards |

### Botões

Todo botão é **laranja com texto branco**; no hover, **laranja claro com texto `#333`**. Não
há variante de cor: `btn-outline`, `btn-ghost` e `btn-neutral` continuam existindo no HTML,
mas quem decide a cor é o sistema.

```css
.btn.btn {
  --btn-color: var(--color-primary);
  --btn-bg: var(--color-primary);
  --btn-fg: var(--color-primary-content);
  background-color: var(--color-primary);
  color: var(--color-primary-content);
}

.btn.btn:hover,
.btn.btn:focus-visible {
  background-color: var(--cork-primary-200);
  color: #333;
}
```

**A regra vive fora de qualquer `@layer`**, no fim do arquivo, e isso não é preferência de
organização. O daisyUI declara `.btn { color: var(--btn-fg) }` e o próprio `--btn-fg` **dentro
de `@layer utilities`** (em sub-camadas próprias, `daisyui.l1.l2…`) — depois da
`@layer components`, onde moram as regras do projeto —, e camada posterior vence
**independentemente da especificidade**; quem não está em camada alguma vence as duas.
Dentro de `@layer components` a regra pintava o fundo — porque o daisyUI lê a nossa
`--btn-color` — e perdia a cor do texto: o sintoma foi a seta preta sobre o laranja, que
sobreviveu a duas tentativas de resolver por especificidade. Quando algo de botão não pegar,
confira a camada antes da especificidade.

**E não é só de botão.** A regra vale para **qualquer propriedade que o daisyUI também
declare**: `.btn-square { width }`, `.table :where(th,td) { padding-inline }`,
`.btn { cursor }` — o da página atual da paginação — e o que mais vier. Em `@layer components`
elas perdem, e perdem em silêncio — a regra aparece no CSS servido, o `grep` a encontra, e
mesmo assim o navegador aplica a do daisyUI. Foi o que aconteceu com a largura do botão da
melhor conversa e o padding da coluna de variação: as duas ficaram sem efeito até saírem da
camada (medido: botão parado em 32px onde a regra pedia 34; coluna com os 16px do daisyUI onde
a regra pedia 9,6). Conferido no CSS servido em 10/09/2026, com daisyUI 5.7.22, contando as
chaves regra por regra: `.btn` e `.btn-square` caem em `utilities`, as regras do projeto em
`components`, e o bloco do fim do arquivo, fora de camada.

Conferir isso exige medir no navegador, porque ler o CSS não revela o problema. O caminho
usado foi baixar a página e as folhas servidas, inliná-las num arquivo local e abri-lo com
o Chrome da imagem de testes — que assim não esbarra no `config.hosts` da produção.

O ícone dentro do botão **não tem regra própria**: os SVGs do Phosphor são
`fill: currentColor`, então a seta é branca no repouso e `#333` no hover porque acompanha a
cor do botão. Se algum dia um ícone aparecer escuro sobre o laranja, o problema é a `color`
do botão, não o SVG.

Vale para **todos** os botões, com o mesmo comportamento — inclusive as setas do calendário,
as do modal do dia e as da paginação, que passaram a ter seta junto do texto.

A única exceção é o **grupo de escolha** (`join-item`: os itens por página e os números da
paginação): a opção selecionada fica no laranja cheio e as demais assumem o formato do hover —
branco com `#333` e borda laranja —, invertendo para laranja ao passar o mouse. Sem isso o
grupo inteiro vira um bloco laranja e não dá para ver o que está escolhido.

Na paginação a página atual é um `<span>`, e não um link: não há para onde ir. O cursor dela
volta a `default` numa regra fora de `@layer`, pelo mesmo motivo das regras de botão acima —
dentro da camada, o `cursor` do `.btn` do daisyUI vence.

`btn--field` alinha a altura do botão à dos campos numa barra de filtros, e `btn-sm` é
tamanho, não cor.

O menu é a exceção: como fica sobre a barra escura, o item ativo usa `--color-primary`
direto e o hover é `color-mix(in oklab, white 8%, transparent)` — token claro sobre fundo
escuro não teria contraste.

Tipografia: **Montserrat**, servida pelo próprio app (`@font-face` em
`app/assets/stylesheets/application.css`, arquivos `.woff2` em `app/assets/fonts/`, subsets
`latin` e `latin-ext`, peso variável), corpo em 0.875rem, `letter-spacing: 0` em toda a
hierarquia e `tnum` ligado para as colunas de valor.

## Decisões

- **Sinal de arquivo no header, em vez de um status decorativo.** A versão inicial trazia
  uma pílula "Carteira BIN" sempre verde, ligada a nada. O layout passou a mostrar, em toda
  página, o único dado operacional que importa todo dia: há quanto tempo o último arquivo
  entrou. A regra é a mesma do card da tela de importação (`ImportBatch.days_since_last_file`).
- **Grupo do menu não entra na trilha.** "Dashboard" e "Operação" agrupam páginas; não são
  destinos navegáveis e por isso não aparecem no breadcrumb.
- **A busca procura dados, não páginas.** A versão inicial abria uma lista fixa das
  páginas — que já estão no menu. Agora o campo consulta `GET /search?q=` e o resultado
  chega num Turbo Frame (`target="_top"`, para o clique navegar a página inteira): subcanais
  (abrem o relatório de faturamento do subcanal) e estabelecimentos (abrem o cadastro, com
  link "ver todos" para a lista filtrada). O filtro de estabelecimentos é o mesmo da lista
  (`Establishment.search`), para os dois lugares acharem a mesma coisa. Mínimo de
  `GlobalSearch::MIN_LENGTH` caracteres; 200ms de espera após parar de digitar.
- **Hover e ativo são estados diferentes.** No menu, passar o mouse usava o mesmo fundo
  do item ativo, o que fazia parecer que a página corrente mudava.
- **Menu horizontal, não sidebar.** A primeira versão desta branch trazia a sidebar do
  template Cork; voltou a barra escura do layout anterior, adaptada aos dois grupos da
  estrutura nova (divisor fino entre os grupos) e com a busca e o sinal de arquivo dentro dela.
  O que sobreviveu do Cork foi o resto da casca: cards, trilha, tokens `--cork-*`.
- **Diálogo de busca com foco previsível.** Ao abrir, o foco vai para o campo de filtro; ao
  fechar, volta para quem abriu; `Tab` não sai do diálogo, como `aria-modal` promete.
- **Nada vem de fora da origem.** A CSP está ligada
  (`config/initializers/content_security_policy.rb`) com `default_src :self` e nonce por
  requisição no `script-src`; `style-src` aceita `unsafe-inline` porque o Turbo escreve
  estilo inline ao animar a troca de página e o nonce não chega lá. Por isso a Montserrat foi
  vendorizada em `app/assets/fonts/`, como os ícones Phosphor. O teste
  `test/controllers/content_security_policy_test.rb` falha se alguma página voltar a carregar
  recurso externo.

## O que ficou como está, e por quê

- **Cadastro manual saiu desta versão.** As rotas, a tela e o botão foram removidos do
  portal; a operação `Operations::RegisterManually` e seus testes ficam, porque a regra de
  identidade (EC preso ao CNPJ e ao canal) continua valendo e o cadastro volta no futuro.
- **Metabase fica em Operação, com explicação.** É ferramenta de apoio para o operador, não
  relatório; a página diz o que é, como usar e esconde os dados de conexão num `details`.
- **Trilha na página inicial** mostra `Início / Faturamento`, com "Início" apontando para a
  própria página.

## Verificação

Sem overflow horizontal em 390px (`scrollWidth == innerWidth` nas quatro páginas medidas) —
**medição manual da época, não reproduzida por teste**: não há caso de sistema que a refaça.
Contorno de foco visível em todo elemento focável (3px, `:focus-visible` no `@layer base`).
`prefers-reduced-motion` zera as transições.

Suíte: `bin/rails test` cobre trilha, sinal de arquivo e a ligação da busca em
`test/controllers/reports_controller_test.rb`, e os resultados em
`test/controllers/search_controller_test.rb`. Os dois controles de filtro da tela de subcanal
(calendário de intervalo e multiselect) têm teste de sistema em
`test/system/sub_channel_filters_test.rb`, que roda em `docker compose run --rm test`. As
tabelas são verificadas de uma vez por `test/controllers/table_accessibility_test.rb`: todo
cabeçalho declara `scope` e toda área rolável é uma região focável.

Para inspecionar o layout com o navegador real, `selenium-webdriver` já está no bundle: o
Selenium Manager baixa o chromedriver sozinho. Capturas via `--headless --screenshot` do
Chrome cortam a página abaixo de ~480px de largura por limite de janela do próprio Chrome —
não é overflow do layout.
