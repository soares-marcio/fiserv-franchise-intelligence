# CLAUDE.md

Diretrizes deste projeto. Complementa, não substitui, as instruções globais do usuário.

## 0. Honestidade e fidelidade aos fatos (prevalece sobre todo o resto)

**Nunca invente dados, números, fatos, fontes ou nomes. Seja fidedigno à evidência.**

Aqui isso não é abstrato: o projeto audita faturamento real. Um número estimado apresentado como
apurado vira decisão errada sobre a carteira de um cliente.

- Use só informação verificável e diga de onde veio (coluna da planilha, tabela, commit, log).
- Separe **fato** de **inferência**. Nunca apresente suposição como constatação.
- Quando não der para confirmar, **declare a lacuna** — "não verifiquei", "não consegui rodar" —
  em vez de estimar ou preencher com suposição.
- Ao avaliar se algo funciona, relate o que foi de fato testado e o que não foi. Contornar um
  problema manualmente não é o mesmo que corrigi-lo: diga qual dos dois aconteceu.
- Se não sabe, diga. Uma lacuna declarada vale mais que um palpite confiante.

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

Ao mexer em qualquer um desses caminhos, teste em banco recém-criado (ver abaixo), não só com o
banco que já está na sua máquina.

Um quarto tinha data para quebrar e foi desarmado antes: as competências das colunas de
volume do Mapa (`VOLUME DE FATURAMENTO ... AAAAMM`) **avançam a cada planilha semanal** e a
validação as aceita por forma, não por lista fixa — o contrato é que **as quatro famílias
tragam o mesmo conjunto de meses**, e a parte fixa do cabeçalho continua literal e fatal em
qualquer divergência. `DEFAULT_VOLUME_MONTHS` existe só para as planilhas sintéticas dos
testes. O teste da virada de mês vive em `test/services/template_volume_months_test.rb`.

## Modelo de remuneração

**`STATUS ANTECIP AUTO NO BOARDING` não diz se o EC tem antecipação.** Na planilha real a
coluna só aparece com `0` ou vazia — nenhum valor positivo —, então qualquer regra baseada
nela classifica todo mundo como "sem" ou "indefinido" e nunca "com". A classificação foi
removida da apuração até a fonte correta ser definida; a tela apresenta as duas hipóteses.
Candidatas em avaliação: `SOLUÇÕES FINANCEIRAS` (valores `Auto`, `Flex`, `Combo`, `NÃO` —
vocabulário idêntico ao do slide) e o volume de antecipação realizado
(`monthly_volumes.metric = 'antecipacao'`). As duas divergem entre si: 502 ECs se declaram
`Auto`, mas só 248 antecipam de fato.

As faixas e alíquotas do modelo da Fiserv vivem **só** em `SubChannelCompensationRules`.
Quem alterar alíquota mexe lá e em nenhum outro lugar — e, como a view
`audit_accreditation_earnings` congela esses `CASE WHEN` no banco, a mudança exige migração
recriando a view e regeneração do `structure.sql`. Não derive classificação de antecipação das
colunas atuais. Quando os valores com e sem antecipação divergem, apresente o intervalo e deixe
a definição pendente até existir uma fonte confiável.

## Schema, `structure.sql` e produção

O banco é **descartável** nesta fase e será recriado muitas vezes. O caminho para isso é um só:

```bash
bin/rails db:rebuild   # DROP … WITH (FORCE) → create → schema:load → seed, para dev e teste
```

Pode rodar com os containers de pé: o `FORCE` derruba as conexões deles. O `web` reconecta
na requisição seguinte, mas o `worker` **encerra** — na janela em que o banco não existe o
`bin/jobs` levanta `ActiveRecord::NoDatabaseError`, e o supervisor do Solid Queue reergue os
processos filhos dele, não a si mesmo. Quem o traz de volta é o `restart: unless-stopped`
declarado no `docker-compose.yml`; sem ele o container fica `Exited` e as filas param caladas.

O que esse caminho garante, e por quê cada peça importa:

1. **`db/structure.sql` é a fonte da verdade** — é o que produção, o CI e o banco de teste
   carregam. Ele é gerado, nunca editado à mão. Para regenerá-lo a partir das migrations,
   mova-o de lugar antes de `db:drop db:create db:migrate`; com o arquivo presente, um
   `db:migrate` em banco vazio **carrega o arquivo em vez de rodar as migrations**, e ao
   final ainda o sobrescreve com um dump do banco.
2. **Tudo que o app precisa tem que estar nele**: as tabelas do Solid Queue, do Solid Cable
   e do Solid Cache (criadas por migration no banco principal — os `db/*_schema.rb` só
   entram em banco separado, e aqui `CABLE_DATABASE_URL`/`CACHE_DATABASE_URL`/
   `QUEUE_DATABASE_URL` apontam para o mesmo banco), as seis views materializadas, a
   partição `daily_revenues_default` e a extensão `pg_trgm`.
3. **O que o dump não carrega vem do seed**: role e GRANT são objetos do cluster, não do
   banco. `db/seeds.rb` cria o `metabase_ro`; `db:prepare` no primeiro deploy roda o seed.
4. **`test/db/schema_integrity_test.rb` é o guarda.** Ele roda contra o banco de teste, que
   nasce do `structure.sql`, e falha se qualquer peça acima faltar ou se o arquivo em disco
   divergir do que está carregado. Foi escrito depois de as tabelas do Solid Cable ficarem
   três dias fora do schema sem ninguém perceber: o broadcast do Turbo falhava em silêncio
   e a tela de importação nunca era avisada.
5. Migration já aplicada em produção é imutável; enquanto o banco é descartável, editar e
   recriar é aceitável — depois do primeiro deploy com dados, só migration nova.

## Dados de cliente

A planilha BIN traz CNPJ, telefone, endereço e faturamento reais. **Nunca** versione, nunca
inclua em fixture, nunca cole em log ou em mensagem. Ela vive em `../franchise-storage/storage/`,
fora do repositório. Testes usam planilha sintética (`test/support/bin_workbook.rb`).

O import pela interface, com o arquivo real, é verificação **do usuário** — não execute por conta
própria.

## Controle de acesso

O portal ainda opera sem autenticação por decisão de escopo. Trate-o como ferramenta interna:
não exponha Rails, PostgreSQL ou Metabase fora de uma máquina ou rede confiável. Antes de qualquer
publicação externa, autenticação e autorização passam a ser requisito de entrega.

## Verificação

`bin/rails test` · `bin/rubocop` · `bin/brakeman` devem passar antes de entregar. A suíte roda em
processo único de propósito (ver `README.md`). Os testes de sistema (`test/system`) ficam fora do
`bin/rails test` e precisam de navegador: rodam pela imagem de testes, `docker compose run --rm
test`, que executa `test:all` (suíte completa, sistema incluído) — obrigatória quando a mudança
toca telas ou JavaScript. A imagem de produção exclui deliberadamente as dependências de
desenvolvimento e teste.

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
