# Layout da interface

Casca visual da aplicação, introduzida na branch `feature/cork-layout-sidebar-breadcrumbs`
sobre o padrão de admin "Cork". Este documento registra a estrutura, as decisões e o que a
revisão de frontend corrigiu, para que a próxima alteração parta do que existe e não do
que parece existir.

## Estrutura

```
┌──────────────────────────────────────────────────────────────┐
│ header (fixo, 3.5rem)   [busca global       Ctrl+/]  [status] │
├───────────────┬──────────────────────────────────────────────┤
│ sidebar       │ breadcrumb                                   │
│ (17.5rem,     │ ┌──────────────────────────────────────────┐ │
│  ≥1280px      │ │ page-hero                                │ │
│  fixa;        │ └──────────────────────────────────────────┘ │
│  <1280px      │ ┌──────────────────────────────────────────┐ │
│  off-canvas)  │ │ filter-panel / table-frame / metric-card │ │
│               │ └──────────────────────────────────────────┘ │
└───────────────┴──────────────────────────────────────────────┘
```

| Peça | Arquivo | O que faz |
| --- | --- | --- |
| Header | `app/views/layouts/_navbar.html.erb` | Marca (só abaixo de 1280px), botão do menu, busca de páginas e o sinal de arquivo |
| Sidebar | idem | Navegação em dois grupos: **Dashboard** (relatórios) e **Operação** (estabelecimentos, importação e Metabase) |
| Busca global | `SearchController`, `GlobalSearch`, `app/views/search/index.html.erb`, `cork_layout_controller.js` | Digita EC, CNPJ, nome, cidade, CNAE ou subcanal e vê subcanais e estabelecimentos ao vivo; `Ctrl+/` (`⌘/` no Mac) abre, `Esc` fecha, `Enter` abre o primeiro resultado |
| Breadcrumb | `ApplicationHelper#render_breadcrumbs` | `Início / <grupo> / <página>`; o grupo é texto, não link |
| Sinal de arquivo | `ApplicationHelper#header_file_status` | Há quanto tempo a carteira recebeu arquivo; vermelho a partir de `ImportBatch::STALE_AFTER_DAYS` |

### Breakpoints

| Largura | Comportamento |
| --- | --- |
| ≥ 1280px | Sidebar fixa à esquerda, abaixo do header; a marca aparece dentro dela e some do header |
| < 1280px | Sidebar off-canvas, aberta pelo botão do header; overlay escurece o conteúdo |
| < 560px | Some o atalho de teclado da busca e o sinal de arquivo (o card na tela de importação continua) |

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
- **Sem a classe `navbar` do daisyUI no header.** Ela impunha `min-height: 4rem` por cima
  dos 3.5rem do `.header`, e a sidebar e o conteúdo eram posicionados para 3.5rem: 8px da
  sidebar ficavam por baixo do header. Medido com Selenium antes (64px) e depois (56px).
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
