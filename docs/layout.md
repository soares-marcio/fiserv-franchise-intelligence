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

### Modal de lançamentos diários

Clicar na linha do estabelecimento, na tela de subcanal, abre `.daily-modal` por Turbo Frame
(`reports/_daily_revenues.html.erb`). Ele mostra **três competências** lado a lado —
penúltimo mês, último e atual —, um dia por linha, com o cabeçalho da tabela colado no topo
ao rolar (o scrollport é a própria tabela, não a página).

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
organização. O daisyUI declara `.btn { color: var(--btn-fg) }` e o próprio `--btn-fg` **sem
camada**, e estilo sem camada vence estilo em camada **independentemente da especificidade**.
Dentro de `@layer components` a regra pintava o fundo — porque o daisyUI lê a nossa
`--btn-color` — e perdia a cor do texto: o sintoma foi a seta preta sobre o laranja, que
sobreviveu a duas tentativas de resolver por especificidade. Quando algo de botão não pegar,
confira a camada antes da especificidade.

**E não é só de botão.** A regra vale para **qualquer propriedade que o daisyUI também
declare**: `.btn-square { width }`, `.table :where(th,td) { padding-inline }`, e o que mais
vier. Em `@layer components` elas perdem, e perdem em silêncio — a regra aparece no CSS
servido, o `grep` a encontra, e mesmo assim o navegador aplica a do daisyUI. Foi o que
aconteceu com a largura do botão da melhor conversa e o padding da coluna de variação: as
duas ficaram sem efeito até saírem da camada (medido: botão parado em 32px onde a regra
pedia 34; coluna com os 16px do daisyUI onde a regra pedia 9,6).

Conferir isso exige medir no navegador, porque ler o CSS não revela o problema. O caminho
usado foi baixar a página e as folhas servidas, inliná-las num arquivo local e abri-lo com
o Chrome da imagem de testes — que assim não esbarra no `config.hosts` da produção.

O ícone dentro do botão **não tem regra própria**: os SVGs do Phosphor são
`fill: currentColor`, então a seta é branca no repouso e `#333` no hover porque acompanha a
cor do botão. Se algum dia um ícone aparecer escuro sobre o laranja, o problema é a `color`
do botão, não o SVG.

Vale para **todos** os botões, com o mesmo comportamento — inclusive as setas do calendário,
as do modal do dia e as da paginação, que passaram a ter seta junto do texto.

A única exceção é o **grupo de escolha** (`join-item`, hoje os itens por página): a opção
selecionada fica no laranja cheio e as demais assumem o formato do hover — branco com `#333`
e borda laranja —, invertendo para laranja ao passar o mouse. Sem isso o grupo inteiro vira
um bloco laranja e não dá para ver o que está escolhido.

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
