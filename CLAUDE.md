# CLAUDE.md

Diretrizes deste projeto. Complementa, não substitui, as instruções globais do usuário.

## O que é

Auditoria de faturamento da carteira BIN da Fiserv. Importa a planilha mensal, consolida o
faturamento diário por estabelecimento e compara o mês corrente com o anterior em períodos de
mesma duração. Ver `README.md` para glossário de domínio, setup e formato da planilha.

## Convenção de idioma

**Código em inglês. Comentários em português. Interface em português.**

| O quê | Idioma | Exemplo |
| --- | --- | --- |
| Colunas de tabela, models, métodos, variáveis, classes, arquivos | inglês | `legal_name`, `PeriodCoverage`, `max_known_day` |
| Comentários no código | português | `# O corte observado nunca superestima a cobertura.` |
| Textos de tela, rótulos, mensagens de erro ao usuário | português | `"Envie um arquivo .xlsx."` |
| Nomes de teste | português | `test "recusa EC que muda de CNPJ entre importações"` |

Comente o **porquê**, não o quê.

### Exceções deliberadas

Estes identificadores **não** são traduzidos, porque são designações legais brasileiras ou
códigos da Fiserv, e traduzir perderia precisão:

`cnpj` · `ec` · `cep` · `cnae_code` · `cnae_description` · `net_mdr`

### Regra inviolável: cabeçalhos da planilha são literais

As strings que representam colunas do arquivo da Fiserv (`BinImport::Template::EXPECTED_HEADERS`
e qualquer `row["..."]`) são **dados de entrada**, não código. Ficam exatamente como a Fiserv
entrega, incluindo os que estão em minúsculas e parecem nomes de variável:

```ruby
row["fat_total_m1"]        # cabeçalho da planilha — NUNCA renomear
row["motivo_entrada_vip"]  # idem
row["agenda_semanal"]      # idem
snapshot.previous_month_total  # coluna do banco — em inglês
```

Renomear um desses quebra o import com "Cabeçalhos divergentes". Antes de qualquer refactor
que toque strings, confira que `EXPECTED_HEADERS` continua idêntico.

### Rastreabilidade planilha → banco

Toda coluna originada da planilha carrega um `COMMENT` no Postgres, em português, apontando a
coluna e a aba de origem. Ao adicionar coluna nova vinda do arquivo, inclua o comentário:

```ruby
t.date :accredited_on, comment: "Origem: coluna \"DATA DE CREDENCIAMENTO\" da aba Mapa de Clientes BIN"
```

## Particularidades que já causaram bug

O banco é **descartável** nesta fase: será apagado muitas vezes até o schema estabilizar. Três
comportamentos só aparecem em banco recém-criado, e os três já quebraram o sistema:

1. **Views materializadas nascem `WITH NO DATA`.** `REFRESH ... CONCURRENTLY` exige view populada,
   e `SELECT` numa view não populada levanta erro. Use `AuditViews.populated?` antes das duas coisas.
2. **`REFRESH ... CONCURRENTLY` não roda dentro de transação.** Chame `AuditViews.refresh!` fora
   de qualquer `transaction do`.
3. **Partições de `daily_revenues` precisam existir antes do insert.** Linha que cai na partição
   `default` impede a criação da partição daquele mês depois.

Ao mexer em qualquer um desses caminhos, teste com `db:drop db:create db:migrate`, não só com o
banco que já está na sua máquina.

## Dados de cliente

A planilha BIN traz CNPJ, telefone, endereço e faturamento reais. **Nunca** versione, nunca
inclua em fixture, nunca cole em log ou em mensagem. Ela vive em `../franchise-storage/storage/`,
fora do repositório. Testes usam planilha sintética (`test/support/bin_workbook.rb`).

O import pela interface, com o arquivo real, é verificação **do usuário** — não execute por conta
própria.

## Verificação

`bin/rails test` · `bin/rubocop` · `bin/brakeman` devem passar antes de entregar. A suíte roda em
processo único de propósito (ver `README.md`).

---

# Diretrizes gerais de comportamento

Reproduzidas na íntegra de <https://github.com/soares-marcio/andrej-karpathy-skills/blob/main/CLAUDE.md>,
sem tradução, para não introduzir desvio de sentido.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

Strong success criteria let you loop independently. Weak criteria ("make it work") require
constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to
overcomplication, and clarifying questions come before implementation rather than after mistakes.
