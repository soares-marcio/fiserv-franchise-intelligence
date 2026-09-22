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

Renomear um desses quebra o import. Antes de qualquer refactor que toque strings, confira que
`EXPECTED_HEADERS` continua idêntico.

O que é inviolável é o **nome**, não o conjunto: desde 08/09/2026 a validação exige que toda
coluna esperada exista e ignora as que sobram, porque a Fiserv acrescenta colunas com o tempo
e o importador lê as células pelo nome. Renome segue fatal — aparece como falta e sobra ao
mesmo tempo.

### Rastreabilidade planilha → banco

Toda coluna originada da planilha carrega um `COMMENT` no Postgres, em português, apontando a
coluna e a aba de origem. Ao adicionar coluna nova vinda do arquivo, inclua o comentário:

```ruby
t.date :accredited_on, comment: "Origem: coluna \"DATA DE CREDENCIAMENTO\" da aba Mapa de Clientes BIN"
```

## Particularidades que já causaram bug

O banco **deixou de ser inteiramente descartável em 09/09/2026**, quando entraram as
anotações do cliente (`company_notes`). Até ali, tudo no banco vinha de planilha e uma
reimportação reconstruía o que fosse perdido. A anotação não vem de arquivo nenhum: apagar o
banco a apaga para sempre, e **nenhuma reimportação a traz de volta**. O que protege é o
`bin/db-backup` (dump diário às 3h30 — `launchd` no Mac até o corte para o berry; depois,
cron do berry com espelho no Mac às 4h00 — mais o volume `storage` com os anexos) — antes de
recriar o banco que serve a LAN, ou se restaura, ou se perde.

A anotação foi desenhada para o restore ser possível: ela se liga ao **CNPJ**, não a
`companies.id`, justamente porque id e uuid são regenerados a cada recriação e o CNPJ vem da
planilha. Dá para recriar o banco, reimportar as planilhas e restaurar só
`company_notes` + `action_text_rich_texts` + `active_storage_*` que tudo religa sozinho.

Fora isso, o schema continua mudando e três comportamentos só aparecem em banco recém-criado
— os três já quebraram o sistema:

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

Um quinto é do lado dos testes: a planilha sintética só varia pelo `dcterms:created` do
`.xlsx`, gravado em **segundos**. Dois `import_synthetic_workbook` seguidos, mesmo com nomes
de arquivo diferentes, caem no mesmo segundo, geram o mesmo SHA-256 e o segundo é recusado
com "Arquivo já importado". Quem precisa de dois imports muda o **conteúdo** do segundo —
um dia de faturamento basta. Isolado, o teste que ignorava isso falhava em 6 de 15 execuções.

## Modelo de remuneração

**`STATUS ANTECIP AUTO NO BOARDING` não diz se o EC tem antecipação.** Na planilha real a
coluna só aparece com `0` ou vazia — nenhum valor positivo. Quem diz é **`SOLUÇÕES
FINANCEIRAS`** (`Auto`, `Flex`, `Combo`, `NÃO`), e o Anexo C da Circular de Oferta de Franquia
confirma: a coluna "C" da tabela de credenciamento é "com auto/flex", ou seja, **modalidade
contratada**. A antecipação **realizada** (`monthly_volumes.metric = 'antecipacao'`) é outra
coisa — base de uma remuneração separada (1.1.2-B) —, e foi tratar uma pela outra que fez a
classificação parecer impossível até 09/2026. As duas divergem, e é esperado que divirjam:
502 ECs se declaram `Auto` e 251 antecipam de fato; 13 dos 61 `NÃO` antecipam mesmo assim.

As faixas e alíquotas do modelo da Fiserv vivem **só** em `SubChannelCompensationRules`.
Quem alterar alíquota mexe lá e em nenhum outro lugar — e, como a view
`audit_accreditation_earnings` congela esses `CASE WHEN` no banco, a mudança exige migração
recriando a view e regeneração do `structure.sql`. A fonte das faixas é o **Anexo C** da
Circular de Oferta de Franquia (contrato assinado), que prevalece sobre os slides de onde o
modelo saiu — as faixas conferem valor a valor entre os dois.

EC sem modalidade na origem continua indefinido: a apuração devolve `NULL`, não zero, e a tela
volta a mostrar o intervalo só para ele. Nunca eleja uma coluna em silêncio.

**`NET MDR` é o MDR líquido realizado do mês anterior ao do arquivo**, não o do mês do
arquivo — provado contra o extrato da Fiserv de agosto/2026 (o arquivo de setembro reproduz
o realizado de agosto em 110 de 112 CNPJs). A recorrência ancora a competência P no último
arquivo de P + 1; ancorar no arquivo de P usa o MDR de P − 1 e já zerou um repasse que a
Fiserv pagou. A campanha APP (R$ 30) é **por CNPJ, no mês do primeiro acesso** — e o arquivo
só traz o "último acesso", então sem um lote anterior sem acesso a view cai em M0. As
fórmulas do extrato, aba a aba, estão no `README.md` ("Como a Fiserv compõe o extrato").

## Schema, `structure.sql` e produção

O projeto ainda está em construção: **não há deploy de produção**, o schema continua mudando
e o banco segue descartável por decisão. O que mudou é o custo de descartá-lo. A stack sobe
`web` e `worker` com `RAILS_ENV=production` apontando para
`fiserv_franchise_intelligence_development` (`docker-compose.yml:28,62`). **A partir do corte de
09/2026 (data no README, "Levar o sistema para outra máquina"), a stack que serve a LAN roda
no berry** (`ssh berry`, clone em `~/repos/franchise-intelligence`,
sobreposição `docker-compose.berry.yml` ativada pelo `COMPOSE_FILE` do `.env` de lá) — é o
banco de lá que tem os lotes importados e as anotações. Recriá-lo custa reimportar as
planilhas à mão, e o import com o arquivo real é operação do usuário. A cadeia de deploy
depois do merge é `ssh berry ~/repos/franchise-intelligence/bin/deploy`, que faz o backup
antes do build porque a migração corre no `db:prepare` do entrypoint. Nada no berry se
altera por conta própria: `bin/deploy`, Caddyfile e cron são ações combinadas com o usuário.

No Mac, o `_development` voltou a ser só desenvolvimento (uma cópia congelada do dia do
corte, sem nada que não exista no berry). Mesmo assim:

```bash
RAILS_ENV=test bin/rails db:rebuild   # DROP … WITH (FORCE) → create → schema:load → seed
```

**Sem o `RAILS_ENV=test`, o `db:rebuild` derruba também o banco de development**
(`lib/tasks/db_rebuild.rake:39` acrescenta o banco de teste quando o ambiente é development,
e o de development é o atual). Recriar o de development é legítimo enquanto o schema não
estabiliza — só não deve ser acidente. No dia a dia, mudança de schema entra por
`bin/rails db:migrate`.

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
   `QUEUE_DATABASE_URL` apontam para o mesmo banco), as cinco views materializadas, a
   partição `daily_revenues_default` e as quatro extensões — `pg_trgm`, `pgcrypto`,
   `unaccent` e `vector` (o guarda do item 4 confere só a `pg_trgm`).
3. **O que o dump não carrega vem do seed**: role e GRANT são objetos do cluster, não do
   banco. `db/seeds.rb` cria o `metabase_ro`; `db:prepare` no primeiro deploy roda o seed.
4. **`test/db/schema_integrity_test.rb` é o guarda.** Ele roda contra o banco de teste, que
   nasce do `structure.sql`, e falha se qualquer peça acima faltar ou se o arquivo em disco
   divergir do que está carregado. Foi escrito depois de as tabelas do Solid Cable ficarem
   três dias fora do schema sem ninguém perceber: o broadcast do Turbo falhava em silêncio
   e a tela de importação nunca era avisada.
5. **Enquanto não houver deploy de produção, editar migration e recriar é aceitável** — mas
   editar uma migration já aplicada não muda o banco de development, só o `structure.sql`, e
   o guarda do item 4 passa a acusar divergência até o banco ser recriado. Ou se recria (com
   backup antes), ou se escreve migration nova. Depois do primeiro deploy com dados, só
   migration nova.
6. **`db:migrate` em development regenera o `structure.sql` com as partições vivas.** O dump
   sai do banco, e o banco tem as partições mensais criadas pelos imports
   (`daily_revenues_202607`, `…202608`, `…202609`). Elas não pertencem ao arquivo, que só
   declara a `default`. O diff aparece como não versionado; descarte com
   `git checkout -- db/structure.sql`.
7. **O dump depende de um `pg_dump` no PATH, e ele é keg-only.** Nesta máquina vem do
   `libpq` do Homebrew (`/opt/homebrew/opt/libpq/bin`), que o shell de login tem e um shell
   não interativo pode não ter. Sem ele o `db:migrate` **aplica a migration e falha no
   dump** ("make sure that pg_dump is installed in your PATH"), deixando banco e arquivo
   fora de sincronia sem alarde. A saída que não depende do PATH é a imagem de teste, que
   traz `postgresql-client`; como ela não monta o repositório, o arquivo sai pela saída
   padrão:

   ```bash
   RAILS_ENV=test bin/rails db:migrate
   docker compose run --rm -T test sh -c 'bin/rails db:schema:dump >/dev/null; cat db/structure.sql' > /tmp/structure.sql
   # Arquivo intermediário porque redirecionar direto trunca o destino antes de o dump sair:
   mv /tmp/structure.sql db/structure.sql
   RAILS_ENV=test bin/rails db:rebuild      # confere que o arquivo novo carrega
   ```

   Os dois geradores concordam: com o servidor em 16, o `pg_dump` 18.6 do host e o 17.11 da
   imagem produzem arquivos **idênticos**, porque `lib/tasks/structure_sql.rake` remove o
   `SET transaction_timeout` que as versões acima da 16 emitem.

## Dados de cliente

A planilha BIN traz CNPJ, telefone, endereço e faturamento reais. **Nunca** versione, nunca
inclua em fixture, nunca cole em log ou em mensagem. Ela vive em `../franchise-storage/storage/`,
fora do repositório. Testes usam planilha sintética (`test/support/bin_workbook.rb`).

O import pela interface, com o arquivo real, é verificação **do usuário** — não execute por conta
própria.

## Controle de acesso

O portal ainda opera sem autenticação **própria** por decisão de escopo. Na LAN isso significa
o que sempre significou: quem alcança `http://fiserv.bin` faz tudo. Postgres e Metabase seguem
sem exposição fora de máquina ou rede confiável.

**Desde 22/09/2026 há um endereço público**, `https://manager.melopay.com.br`, servido por
Cloudflare Tunnel (README, "Acesso pela internet"). O requisito de autenticação para
publicação externa é cumprido **fora do app**, pelo Cloudflare Access: a política
`Autorizados` (Allow → lista de e-mails, código de uso único) barra no edge, e sem sessão
válida toda rota responde `302` para o login — `/up` inclusive. Três consequências que
precisam estar na conta de quem mexer nisso:

- **Quem passa pelo gate tem tudo**: ler a carteira inteira, importar planilha e descartar
  lote (irreversível pela tela). Não há papéis, e a anotação continua sem autor. O controle
  é a lista de e-mails, e nada mais.
- **A camada é única**: apagar ou afrouxar a política deixa o portal aberto ao mundo, porque
  não existe login por trás. Autenticação no Rails segue sendo o caminho para defesa em
  profundidade — e traria o autor das anotações junto.
- **O TLS termina na Cloudflare**: CNPJ e faturamento trafegam em claro dentro da
  infraestrutura deles. É inerente ao túnel; a alternativa seria VPN.

Nada disso muda o app: `force_ssl` e `assume_ssl` continuam desligados (ligar quebra a LAN em
HTTP puro), e o nome público entra por `RAILS_HOSTS`, não por código.

**São duas portas de upload, não uma.** A planilha (`import_batches#create`) valida extensão,
tamanho e assinatura ZIP; os anexos da anotação entram por
`/rails/active_storage/direct_uploads`, cuja rota o app **substitui** — a do engine aceitaria
qualquer tipo e tamanho. `NoteAttachmentsController` recusa antes de criar o blob: lista
fechada de tipos (imagem e PDF), 10 MB, rate limit. Anexo abandonado é purgado diariamente
(`config/recurring.yml`). Isso impede abuso acidental e arquivo grande, **não** impede quem
alcança a rede de subir arquivo — essa parte entra na mesma conta da autenticação.

A anotação também não registra autor, porque não há quem perguntar: fica só a hora da última
edição, como `establishments.duplicate_confirmed_at`.

**O Metabase está desligado no berry** (profile `metabase` no `docker-compose.berry.yml`,
decisão de 18/09/2026; ligar é o "Build futuro: Metabase" do README). A ressalva vale para
o dia em que subir: ele **nunca passou pelo setup inicial** (`/api/session/properties`
respondia `has-user-setup: false` com `setup-token` presente, verificado em 07/09/2026), e
enquanto estiver assim quem alcança o nome na LAN conclui o setup e vira administrador dele.
O Postgres não está exposto na LAN, mas está na rede do Compose, ao alcance do container —
e as views de auditoria carregam CNPJ e faturamento reais. Concluir o setup (com senha)
antes de publicar o nome no Caddy é o mínimo.

## Verificação

`bin/rails test` · `bin/rubocop` · `bin/brakeman` devem passar antes de entregar. A suíte roda em
processo único de propósito (ver `README.md`). Os testes de sistema (`test/system`) ficam fora do
`bin/rails test` e precisam de navegador: rodam pela imagem de testes, que executa `test:all`
(suíte completa, sistema incluído) — obrigatória quando a mudança toca telas ou JavaScript. A
imagem de produção exclui deliberadamente as dependências de desenvolvimento e teste.

**A imagem de testes não monta o repositório: o código entra nela na build** (`Dockerfile`,
alvo `test`, `COPY . .`). Rodar `docker compose run --rm test` sem rebuildar executa o código
de quando a imagem foi criada, e o resultado **passa** — porque ali o código e os testes são
os antigos, coerentes entre si. Um verde assim não diz nada sobre a mudança em curso; custou
uma verificação falsa em 10/09/2026. Sempre as duas linhas, nesta ordem:

```bash
docker compose build test
docker compose run --rm test
```

O sinal de que a imagem está velha é o resultado repetir exatamente a contagem de runs de
antes da mudança, ou uma falha citar marcação que já não existe no repositório.

**Na imagem, `bin/rails test <arquivo>` roda os testes de sistema sem o CSS do app.** O
`app/assets/builds` fica fora da imagem (`.dockerignore`) e o Tailwind só é compilado pelo
gancho de `test:prepare`, que `test:all` e `test:system` executam e o comando `test` com
caminho não. A página então carrega só `application.css` e `actiontext.css`, e qualquer
medida de layout (largura de tabela, transbordo, posição de botão) sai de uma página sem
estilo — custou quatro rodadas em 20/09/2026. Para rodar um arquivo de sistema isolado:

```bash
docker compose run --rm test sh -c "bin/rails tailwindcss:build && bin/rails test test/system/x_test.rb"
```

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
