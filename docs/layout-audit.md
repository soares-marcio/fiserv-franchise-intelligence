# Auditoria da camada de apresentação — Fase 1

Data da inspeção: 2026-09-09

Escopo: `app/assets/tailwind/application.css`, `app/assets/stylesheets/application.css`,
`app/views/**/*.html.erb`, `app/javascript/controllers/*_controller.js` e testes de
controller/system relevantes.

Esta é uma auditoria estática. Não foram inventadas dimensões de tela nem estados de dados.
Onde o resultado depende do CSS compilado, do navegador ou de uma largura não medida, a lacuna
está explicitamente registrada.

## 1. Inventário de cores

Origem principal: bloco `[data-theme="bin"]`, `app/assets/tailwind/application.css:10-56`.

| Função | Tokens e valor declarado | Observação |
| --- | --- | --- |
| Fundo | `--color-base-100: oklch(99% 0.008 78)`; `--color-base-200: oklch(96% 0.018 78)`; `--color-base-300: oklch(90% 0.025 74)` | Superfície principal, fundo e separação/borda. |
| Texto | `--color-base-content: oklch(25% 0.025 50)` | Texto geral. |
| Marca | `--color-primary: oklch(64% 0.19 43)`; `--color-primary-content: oklch(99% 0.008 78)` | `primary-content` duplica `base-100`. |
| Apoio | `--color-secondary: oklch(37% 0.07 198)`; `--color-secondary-content: oklch(98% 0.01 190)`; `--color-accent: oklch(76% 0.14 155)`; `--color-accent-content: oklch(25% 0.055 160)` | Uso específico depende do componente. |
| Neutro | `--color-neutral: oklch(25% 0.025 50)`; `--color-neutral-content: oklch(97% 0.012 75)` | `neutral` duplica `base-content`. |
| Informação | `info: oklch(70% 0.12 235)`; `info-content: oklch(25% 0.065 238)` | Alerta de importação em `import_batches/show.html.erb:34-37`. |
| Sucesso | `success: oklch(72% 0.16 155)`; `success-content: oklch(24% 0.07 157)` | Cards, badges e alertas. |
| Aviso | `warning: oklch(82% 0.16 82)`; `warning-content: oklch(31% 0.08 65)` | Estado de importação e variação. |
| Erro | `error: oklch(70% 0.17 25)`; `error-content: oklch(27% 0.09 22)` | Falhas e variação negativa. |

Derivados e literais encontrados em `application.css:37-54,75,80,87-90,113-126,237-239,
285-311,343-372,420-423,498-501,557,600,611,616,731-735,891-895,1411-1426,1507-1519,
1522-1542,1559-1567,1669-1672,1690-1698,1737-1744,2058-2059,2126-2144,2537-2540,
2572-2631`:

- A casca usa `--cork-*` por `color-mix()`: heatmap 4/9/15/22/30%, primary 12/24%,
  fundos de estado e texto secundário em percentuais declarados no próprio token/regra.
- Há quase-duplicatas nas superfícies: `base-100` misturado com `base-200`, `base-300`
  misturado com branco e `base-content` misturado com transparência.
- Fora dos tokens aparecem `white`, `transparent`, `currentcolor`, sombras
  `rgb(68 47 34 / 7%–16%)`, `rgb(48 35 26 / 12%)`, `rgb(31 22 15 / 35%)`,
  `rgb(255 255 255 / 72%–75%)` e `#333` nas linhas 2588, 2591 e 2623.
- `daisyui.js` contém o catálogo da biblioteca, mas é bundle existente e proibido. A
  auditoria considera ativos da aplicação os tokens do tema `bin` e suas regras consumidoras.

## 2. Auditoria de contraste WCAG 2.2 AA

Os valores foram calculados convertendo os tokens OKLCH do tema para sRGB e aplicando a fórmula
WCAG de contraste relativo. Para texto normal usei 4,5:1; para texto grande, 3:1. Não usei
número estimado para `color-mix()` ou transparência.

| Texto | Fundo | Razão | Resultado |
| --- | --- | ---: | --- |
| `base-content` | `base-100` | 15,63:1 | Passa texto normal |
| `base-content` | `base-200` | 14,31:1 | Passa texto normal |
| `base-content` | `base-300` | 11,91:1 | Passa texto normal |
| `primary-content` | `primary` | 3,53:1 | **Reprova texto normal; só passa texto grande** |
| `secondary-content` | `secondary` | 9,57:1 | Passa texto normal |
| `accent-content` | `accent` | 7,74:1 | Passa texto normal |
| `neutral-content` | `neutral` | 14,74:1 | Passa texto normal |
| `info-content` | `info` | 6,08:1 | Passa texto normal |
| `success-content` | `success` | 6,93:1 | Passa texto normal |
| `warning-content` | `warning` | 7,57:1 | Passa texto normal |
| `error-content` | `error` | 5,41:1 | Passa texto normal |
| `primary` | `base-100` | 3,53:1 | **Reprova texto normal** |
| `secondary` | `base-100` | 9,81:1 | Passa texto normal |
| `accent` | `base-100` | 1,97:1 | **Reprova texto normal** |
| `info` | `base-100` | 2,54:1 | **Reprova texto normal** |
| `success` | `base-100` | 2,25:1 | **Reprova texto normal** |
| `warning` | `base-100` | 1,72:1 | **Reprova texto normal** |
| `error` | `base-100` | 2,80:1 | **Reprova texto normal** |
| `#333` | `base-100` | 12,26:1 | Passa texto normal |
| `#333` | `base-200` | 11,28:1 | Passa texto normal |

Não verificados: `--cork-muted`, `--cork-strong`, labels com opacidade, bordas, fundos
`color-mix()`, heatmap, sombras, transparências do topbar e badges. A razão precisa ser
recalculada com a cor composta efetivamente emitida pelo compilador e navegador.

## 3. Problemas de layout mobile

| Problema | Evidência | Impacto ou lacuna |
| --- | --- | --- |
| Desktop-first | Grids de 4/5 colunas em `application.css:155-164`, sobrescritos por `max-width` em `:2408-2546`. | Contraria o contrato mobile-first e cria cascata difícil de verificar. |
| Tabela larga | `.table-scroll` só recebe `overflow-x:auto` em `:2467-2469`; views usam `nowrap`, por exemplo `establishments/index.html.erb:104`. | No telefone exige gesto; não há regra global explícita contra overflow-x do documento. |
| Datepicker reduzido | `:520-528` esconde `.datepicker__pane--next` até 700px. | Menos contexto simultâneo e navegação adicional. |
| Navegação escondida | `:2427-2465` faz `.primary-nav{display:none}` até abrir `.nav-toggle`. | Fluxo permanece disponível, mas exige ação extra em relação ao desktop. |
| Alvos menores que 44px | `.btn` 2,45rem (`:2305-2311`), nav-link 2,6rem (`:1715-1727`), nav do datepicker 2,25rem (`:545-553`) e remover 1,4rem (`:375-385`). | Reprova o alvo de toque ≥44px; pixels são inferência com raiz de 16px e devem ser medidos no browser. |
| Inputs menores que 16px | `body` 0,875rem (`:65-70`), busca do modal 0,95rem (`:2010-2019`) e filtro sem tamanho próprio. | Pode causar zoom no iOS e leitura menor que o requisito. |
| Densidade | `text-xs/text-sm` em CNPJ, CNAE, endereço e mensagens, por exemplo `establishments/index.html.erb:93-131`. | Risco de leitura reduzida; não foi medida a legibilidade física. |
| CLS provável | Montserrat usa `font-display:swap` em `app/assets/stylesheets/application.css:17-36`; topbar atualiza offset via `ResizeObserver` em `app_layout_controller.js:54-63`. | Risco de troca de métrica e reposicionamento; CLS não foi medido. |

O teste `test/system/layout_and_import_test.rb:46-53` verifica apenas vazamento dos cards,
não o `scrollWidth` do documento em 360/480/768/1024/1280/1440.

## 4. Desktop e paridade

A tabela é uma leitura das regras declaradas, não medição de screenshot. Não há evidência de
inspeção renderizada nos três viewports solicitados.

| Viewport | Regras efetivas previstas | Avaliação baseada no código |
| ---: | --- | --- |
| 1024px | Filtros em 2 colunas (`max-width:1200`); `metric-grid--5` em 3 colunas (`max-width:1400`); cards EC/ganho em 1 coluna; tabela ainda desktop até 900px. | Tabelas densas, mas filtros/cards ocupam mais altura; comparação lateral de cards é perdida. Não medido. |
| 1280px | Filtros na grade base; `metric-grid--5` em 3 colunas; cards EC/ganho em 2 colunas. | Boa área de tabela, mas cinco métricas não ficam em cinco colunas. Não medido. |
| 1440px | Cinco métricas em cinco colunas; cards em 2 colunas; `.table-scroll` visível e headers sticky (`:2259-2277`). | Maior densidade prevista; largura real das colunas e comparação lado a lado não medidas. |

Fluxos que encolhem ou exigem gesto no pequeno, todos observáveis no CSS/ERB:

- tabelas de faturamento, estabelecimentos, importações e calendário rolam horizontalmente no
  bloco em ≤900px; no desktop ficam visíveis sem esse gesto;
- filtros de `reports/sub_channel.html.erb:102-180` passam para uma coluna em ≤900px;
- Dashboard/Operação passam para hambúrguer em ≤900px;
- datepicker perde a segunda pane em ≤700px;
- legenda da marca e texto do atalho de busca somem em ≤560px (`:2486-2490`);
- métricas passam a uma coluna em ≤560px (`:2505-2508`).

Não foi encontrado fluxo de relatório, ordenação, busca, modal diário ou importação removido
do ERB por viewport; a perda acima é de espaço, simultaneidade ou gesto.

## 5. Problemas de UX

Pontos comprovados: importação tem estados pendente, execução, falha, sucesso e ausência em
`import_batches/index.html.erb:35-92`; busca tem vazio em `search/index.html.erb:4-12`;
modal de busca implementa foco, Escape e trap em `app_layout_controller.js:66-140`;
há foco visível em `application.css:80` e reduced motion em `:2548-2555`.

Lacunas:

- Não há estado de carregamento específico no ERB para tabelas/frames durante busca/filtro;
  `live_form_controller.js:15-25` somente sincroniza após o carregamento.
- O upload tem `required` em `import_batches/index.html.erb:13-18`, mas não há mensagem inline
  associada por `aria-describedby` para arquivo ausente/tipo inválido.
- O número de corte tem min/max em `import_batches/show.html.erb:40-46`, sem mensagem inline
  associada para valor fora do intervalo.
- Não há skip link em `application.html.erb:19-32`.
- `search/index.html.erb:16,30` usa `h3` no fragmento; a hierarquia depende do `h2` do
  diálogo em `_navbar.html.erb:80`, portanto precisa ser conferida no DOM completo.
- `copy_report_controller.js:6-8` declara apenas `source,feedback`, mas
  `_failure_report.html.erb:36-38` traz `data-copy-report-target="button"`; target órfão.
- O loading da lista diz `Importando` em `import_batches/index.html.erb:38-43`, enquanto o
  detalhe usa `Importando…` em `:34-37`; inconsistência de estado textual.

## 6. Código morto ou duplicado de apresentação

| Item | Evidência | Classificação |
| --- | --- | --- |
| Breakpoint 1400 | `:166-169` e `:2419-2424`. | Duplicado por função; consolidar sem apagar seletor vivo. |
| Breakpoint 1200 | `:929-933`, `:1015-1019`, `:2408-2416`. | Regras distribuídas/duplicadas. |
| Breakpoint 700 | `:520-528`. | Fora da escala exigida; reescrever em min-width na Fase 2. |
| Breakpoints 900/560 | `:2427-2546`. | Layout antigo desktop-first; candidatos à conversão. |
| Casca duplicada | `:2148-2406` redeclara page-hero, cards, filter, table, btn, badges e fieldset. | Sobrescrita viva, parcialmente redundante; consolidar a cascata. |
| Scrollbar nav | `:1630-1632`; nav usa flex-wrap em `:1621-1628` sem overflow declarado. | Candidato a morto; confirmar estilo importado antes de remover. |
| Target Stimulus | `_failure_report.html.erb:36-38` contra `copy_report_controller.js:7`. | Target `button` morto confirmado; remover só na Fase 2 e preservar o botão. |
| Controllers | Os oito controllers de apresentação têm referência ERB: `app-layout`, `conversation-modal`, `copy-report`, `daily-modal`, `date-range-picker`, `live-form`, `sticky-table` e `tag-select`. | Nenhum controller inteiro sem referência confirmado; não remover. |

## 7. Plano de ação priorizado

| Prioridade | Ação | Impacto | Esforço | Evidência de conclusão |
| ---: | --- | --- | --- | --- |
| 1 | Reescrever a casca mobile-first com `min-width` em 480/768/1024/1280 e retirar os breakpoints antigos. | Alto | Alto | CSS sem layout `max-width`; inspeção em 360/768/1440. |
| 2 | Corrigir pares reprovados ajustando luminância nos tokens existentes. | Alto | Médio | Matriz calculada dos pares efetivos; texto normal ≥4,5:1. |
| 3 | Garantir controles ≥44px e inputs ≥16px sem reduzir densidade desktop. | Alto | Médio | Medição computada em 360/768/1440 e teste de teclado. |
| 4 | Consolidar o bloco duplicado, deixando fora de `@layer` só o que precisa vencer daisyUI. | Alto | Médio | CSS compilado e testes de regressão. |
| 5 | Verificar overflow do documento e dos blocos de tabela em cada breakpoint. | Alto | Médio | `scrollWidth`/clientWidth e acesso por teclado medidos. |
| 6 | Desenhar loading e validação inline associada a campos/frames, sem mudar contratos. | Médio | Médio | Estados default/hover/focus/active/disabled/loading/erro testados. |
| 7 | Remover target órfão e CSS morto somente após busca em ERB, JS e testes. | Médio | Baixo | `rg` sem referência e testes verdes. |
| 8 | Medir sticky header, fonte swap e dimensões reservadas para CLS. | Médio | Médio | Evidência runtime; não declarar aprovação antes da medição. |

## Limitações desta Fase 1

- Não rodei inspeção visual em 360px, 768px, 1024px, 1280px ou 1440px.
- Não compilei Tailwind/daisyUI para obter cores finais de `color-mix()`.
- Não calculei CLS nem `scrollWidth` real do documento por viewport.
- Não alterei CSS, ERB, JavaScript, ícones, testes ou configuração.
- A Fase 2 depende de aprovação explícita; este documento é o único artefato permitido nesta fase.
