# Layout da interface

Casca visual da aplicação, introduzida na branch `feature/cork-layout-sidebar-breadcrumbs`
sobre o padrão de admin "Cork". Este documento registra a estrutura, as decisões e o que a
revisão de frontend corrigiu, para que a próxima alteração parta do que existe e não do
que parece existir.

## Estrutura

```
┌──────────────────────────────────────────────────────────────────────┐
│ topbar (sticky, escura)                                              │
│ [marca]  Faturamento · Parados · Semanal │ Estabelecimentos · Importar · Metabase │ [⌘/] [sinal]
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
| Breadcrumb | `ApplicationHelper#render_breadcrumbs` | `Início / <grupo> / <página>`; o grupo é texto, não link |
| Sinal de arquivo | `ApplicationHelper#header_file_status` | Há quanto tempo a carteira recebeu arquivo; vermelho a partir de `ImportBatch::STALE_AFTER_DAYS` |

### Breakpoints

| Largura | Comportamento |
| --- | --- |
| > 1400px | Uma linha: marca, menu, busca e sinal |
| ≤ 1400px | O menu desce inteiro para a segunda linha da barra |
| ≤ 560px | Somem a legenda da marca e o atalho da busca (fica o ícone); o sinal encolhe |

O menu nunca rola nem corta: quebra linha e a barra cresce o que precisar. A busca na barra
é só ícone + atalho (o texto existe para leitor de tela); o campo de verdade fica no diálogo.

### Ícones

Subconjunto do **Phosphor** (peso regular, MIT) vendorizado em `vendor/icons/phosphor/regular/`,
inlined por `ApplicationHelper#icon` — sem CDN, sem JavaScript, e só entram no repositório os
ícones usados. `icon_label(nome, texto)` monta ícone + texto para botões e links. O ícone é
decorativo (`aria-hidden`); quem dá o significado é o texto ao lado. Para acrescentar um:
baixe o SVG de `github.com/phosphor-icons/core/assets/regular/` para a pasta e use pelo nome.

| Onde | Ícones |
| --- | --- |
| Menu | chart-line-up, pause-circle, calendar-blank, storefront, upload-simple, chart-bar |
| Trilha | house em "Início" |
| Ações | download-simple, funnel, magnifying-glass, eraser, upload-simple, trash, arrow-counter-clockwise, arrow-left, arrow-square-out, list-bullets |
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
| `--cork-primary-100` / `-200` | Fundo do item ativo da sidebar e dos resultados da busca; seleção de texto |
| `--cork-success-100`, `--cork-danger-100`, `--cork-warning-100` | Fundos das badges e do sinal de arquivo |
| `--cork-dark-100` | Hover neutro da sidebar, bordas leves, fundo do atalho |
| `--cork-muted` / `--cork-strong` | Texto secundário / texto de destaque |
| `--cork-shadow` | Sombra única dos cards |

Tipografia: **Montserrat** (Google Fonts, carregada no `<head>`), corpo em 0.875rem,
`letter-spacing: 0` em toda a hierarquia e `tnum` ligado para as colunas de valor.

## Decisões

- **Sinal de arquivo no header, em vez de um status decorativo.** A versão inicial trazia
  uma pílula "Carteira BIN" sempre verde, ligada a nada. O layout passou a mostrar, em toda
  página, o único dado operacional que importa todo dia: há quanto tempo o último arquivo
  entrou. A regra é a mesma do card da tela de importação (`ImportBatch.days_since_last_file`).
- **Grupo da sidebar não é link na trilha.** "Dashboard" e "Operação" agrupam páginas; não
  são destino. A versão inicial os renderizava como link para a raiz, então clicar em
  "Operação" abria o relatório de faturamento.
- **A busca procura dados, não páginas.** A versão inicial abria uma lista fixa das
  páginas — que já estão na sidebar. Agora o campo consulta `GET /search?q=` e o resultado
  chega num Turbo Frame (`target="_top"`, para o clique navegar a página inteira): subcanais
  (abrem o relatório de faturamento do subcanal) e estabelecimentos (abrem o cadastro, com
  link "ver todos" para a lista filtrada). O filtro de estabelecimentos é o mesmo da lista
  (`Establishment.search`), para os dois lugares acharem a mesma coisa. Mínimo de
  `GlobalSearch::MIN_LENGTH` caracteres; 200ms de espera após parar de digitar.
- **Hover e ativo são estados diferentes.** Na sidebar, passar o mouse usava o mesmo fundo
  do item ativo, o que fazia parecer que a página corrente mudava.
- **Menu horizontal, não sidebar.** A primeira versão desta branch trazia a sidebar do
  template Cork; voltou a barra escura do layout anterior, adaptada aos dois grupos da
  estrutura nova (divisor fino entre os grupos) e com a busca e o sinal de arquivo dentro dela.
  O que sobreviveu do Cork foi o resto da casca: cards, trilha, tokens `--cork-*`.
- **Diálogo de busca com foco previsível.** Ao abrir, o foco vai para o campo de filtro; ao
  fechar, volta para quem abriu; `Tab` não sai do diálogo, como `aria-modal` promete.

## O que ficou como está, e por quê

- **Montserrat via Google Fonts.** Funciona porque a CSP está desativada. É uma requisição
  externa em toda página; se a ferramenta for usada em rede restrita ou a CSP for ligada,
  vendorize a fonte em `vendor/fonts` como já se faz com os ícones Phosphor.
- **Cadastro manual saiu desta versão.** As rotas, a tela e o botão foram removidos do
  portal; a operação `Operations::RegisterManually` e seus testes ficam, porque a regra de
  identidade (EC preso ao CNPJ e ao canal) continua valendo e o cadastro volta no futuro.
- **Metabase fica em Operação, com explicação.** É ferramenta de apoio para o operador, não
  relatório; a página diz o que é, como usar e esconde os dados de conexão num `details`.
- **Trilha na página inicial** mostra `Início / Dashboard / Faturamento`, com "Início"
  apontando para a própria página. É o padrão do template; inofensivo.

## Verificação

Sem overflow horizontal em 390px (`scrollWidth == innerWidth` nas quatro páginas medidas).
Contorno de foco visível nos links da sidebar (3px). `prefers-reduced-motion` zera as
transições. Suíte: `bin/rails test` cobre trilha, sinal de arquivo e a ligação da busca em
`test/controllers/reports_controller_test.rb`, e os resultados em `test/controllers/search_controller_test.rb`.

Para inspecionar o layout com o navegador real, `selenium-webdriver` já está no bundle: o
Selenium Manager baixa o chromedriver sozinho. Capturas via `--headless --screenshot` do
Chrome cortam a página abaixo de ~480px de largura por limite de janela do próprio Chrome —
não é overflow do layout.
