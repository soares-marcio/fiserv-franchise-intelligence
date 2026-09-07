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
│            Clientes parados   Importar arquivo                               │
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
| ≤ 1200px | A barra de filtros da tela de subcanal passa a duas colunas |
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
| Menu | chart-line-up, pause-circle, calendar-blank, calendar-check, chart-bar, storefront, upload-simple, caret-down (indicador de cada grupo), list-bullets (hambúrguer) |
| Trilha | house em "Início" |
| Ações | download-simple, funnel, magnifying-glass, eraser, upload-simple, trash, arrow-counter-clockwise, arrow-left, arrow-square-out, x (fechar a busca) |
| Variação | trend-up, trend-down e minus, em peso **duotone**, por `ApplicationHelper#phosphor_icon` |
| Cards da importação | calendar-check, file-arrow-up, cpu |

### Busca ao vivo na lista de estabelecimentos

O formulário de busca mira o Turbo Frame `establishments` que envolve a listagem
(`data-turbo-frame`), com `data-turbo-action="advance"` para a URL acompanhar o filtro. O
controller Stimulus `live-form` submete 250ms depois da última tecla; o botão e o Enter
continuam funcionando sem JavaScript. É o mesmo mecanismo da busca global.

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
