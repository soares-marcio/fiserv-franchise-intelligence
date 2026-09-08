# Fiserv Franchise Intelligence

Auditoria de faturamento da carteira BIN. Importa a planilha mensal que a Fiserv entrega,
consolida o faturamento diário por estabelecimento e compara o mês corrente com o anterior
em períodos de mesma duração.

## Glossário

| Termo | Significado |
| --- | --- |
| **Master** | Como a interface chama o **canal** da carteira. É o vocabulário do negócio e o dos próprios dados: o canal importado chama-se `MASTER FRANQUEADO ...`. No banco, no código e nas mensagens do import a palavra continua sendo `channel` / `CANAL` — esta última porque aponta uma coluna da planilha com esse nome. |
| **MIC** | Como a interface chama o **subcanal**. Idem: os dez subcanais da carteira se chamam `MIC ...`. No banco é `sub_channel`; na planilha, `SUB-CANAL`. |
| **EC** | Código do estabelecimento comercial (8 dígitos). |
| **Competência** | Mês de referência do faturamento, sempre no primeiro dia do mês. |
| **M-1** | Competência anterior à que está aberta. |
| **Dia de corte** (`max_known_day`) | Último dia do mês atual coberto pelo arquivo. |
| **Mês anterior cheio** | Faturamento do M-1 sem recorte — o mês fechado inteiro. |
| **Base comparável** | Faturamento do M-1 recortado no mesmo dia de corte do mês atual. |
| **Variação alinhada** | Mês atual ÷ base comparável. Comparar com o mês cheio subestima a carteira. |
| **M0/M1/M2 (credenciamento)** | Os três primeiros meses de um EC, contados de `accredited_on`. M0 é a competência inteira do credenciamento ("fração de mês é mês cheio"). |
| **Prêmio de entrada** | Remuneração por credenciamento, por faixa de faturamento mensal do EC, apurada por **marca d'água**: paga-se em M0 o valor da faixa e, em M1/M2, só a diferença quando a faixa do mês supera o já pago. Mais R$ 30 de digitalização, uma única vez em M0, para EC com acesso ao app. |
| **Repasse recorrente** | Alíquota (débito e crédito, escolhidas pela faixa de **Net MDR da carteira**) × volume da modalidade. Vitalício, desde a primeira transação. |
| **Acelerador / redutor** | Mutuamente exclusivos, mês contra mês ("MxM"): crescimento ≥ 20% remunera um % do faturamento **incremental**; queda aplica um % de redução sobre a **remuneração**. Entre 0% e 19,99% de crescimento não há ajuste. |
| **Página 3M** | Janela de 3 meses de calendário à escolha do usuário, com débito/crédito por competência (`monthly_volumes`) e o modelo de remuneração aplicado por sub-canal e por EC. |
| **Cliente parado** | Empresa (CNPJ) cuja última venda está a `AuditViews::STALLED_THRESHOLD` dias ou mais do dia de corte — hoje 7. Quem nunca vendeu no mês conta o corte inteiro. |

Quando o recorte cobre mais de um canal, usa-se o **menor** dia de corte disponível: comparar
períodos de durações diferentes entre canais distorceria a variação.

Gabaritos oficiais da Fiserv: carteira de R$ 582.000 (45% débito, 55% crédito) na faixa
0,35–0,39% rende R$ 157,14 + R$ 384,12 = **R$ 541,26** — este é teste de aceitação em
`test/services/sub_channel_compensation_rules_test.rb`. Credenciamento com meses de
18k/15k/55k paga R$ 50, nada e R$ 39, total igual à faixa do mês de pico — também teste de
aceitação, no mesmo arquivo; a regra da marca d'água ponta a ponta, pela view, é coberta por
`test/services/three_month_earnings_test.rb`.

## Contagens e rótulos da tela de subcanal

Quatro números da tela são derivados, e a regra de cada um é decisão registrada — não convém
adivinhar pela tela:

- **ECs e CNPJs não se misturam.** A listagem tem **uma linha por EC**, porque cada EC tem
  faturamento próprio; as abas e as contagens do topo somam **CNPJs distintos**. Um cliente
  com dois ECs conta um no rótulo e ocupa duas linhas na tabela.
- **Ativo ou suspenso é do cliente, não do ponto de venda.** Um CNPJ é ativo se tiver ao
  menos um EC ativo (`STATUS DO CONTRATO`, da aba Mapa de Clientes BIN) e só entra em
  suspensos quando **todos** os ECs dele estão suspensos. Na carteira real, oito dos nove
  CNPJs com status misto são troca de EC — o antigo suspenso, o novo aberto no lugar —, e
  contá-los como suspensos marcaria como parado quem apenas migrou. Cada rótulo leva a regra
  em tooltip. O contrato só tem dois status; se surgir um terceiro, ele cai em suspensos e o
  cálculo precisa mudar.
- **Ticket médio** = mês anterior cheio ÷ CNPJs **ativos** do recorte. Mistura o mês fechado
  com o status de hoje de propósito — a leitura é "quanto rende cada cliente ativo" —, e por
  isso a tela escreve o divisor ao lado do valor. Sem CNPJ ativo o card mostra `—`: zero seria
  outra afirmação.
- **Base zero não vira percentual.** Sem faturamento no mês anterior não há divisão possível,
  e a variação sai como rótulo: **Novo** (vendeu agora, primeira venda na base), **Voltou a
  vender** (ativação antiga, estava zerado e voltou — mora na aba de queda, porque é atenção,
  não crescimento) e **Sem venda** (zerado nos dois períodos).

## Onde ficam as coisas

O repositório não guarda planilha de cliente. O layout esperado é:

```
fiserv/
├── franchise-intelligence/   este repositório
└── franchise-storage/
    ├── storage/              planilhas BIN da Fiserv
    └── images/               material de apoio
```

O teste de referência procura a planilha em `../franchise-storage/storage/` e é pulado
quando ela não está lá. `BIN_REFERENCE_FILE` sobrescreve o caminho.

## Requisitos

- Ruby 4.0.6 (`.ruby-version`)
- PostgreSQL 16 com as extensões que o `structure.sql` declara — `pg_trgm`, `pgcrypto`,
  `unaccent` e `vector` (a imagem `pgvector/pgvector:pg16` traz as quatro)

## Setup

```bash
cp .env.example .env          # defina METABASE_RO_PASSWORD e SECRET_KEY_BASE
docker compose up -d db
bin/setup                     # termina subindo o bin/dev; use --skip-server para não subir
```

Tudo em contêiner (app, worker, banco e Metabase):

```bash
docker compose up
```

O portal ainda não possui autenticação. Enquanto essa camada não for implementada, exponha
as portas somente em uma máquina ou rede confiável; não publique o Compose diretamente na
internet.

### Acesso pela rede

Na LAN o portal é servido por um Caddy em outra máquina, que faz proxy de `http://fiserv.bin`
para `web` e de `http://fiserv-metabase.bin` para `metabase`; o DNS local resolve os dois
nomes. Para isso o Compose publica `3000` e `3001` no IP da LAN (`APP_BIND_IP` no `.env`) e
o Postgres só em `127.0.0.1`. Em produção o app aceita apenas `Host: fiserv.bin` e
`localhost` (`RAILS_HOSTS` acrescenta outros); `force_ssl` fica desligado enquanto o Caddy
servir HTTP puro — liga-se quando ele passar a terminar TLS.

A imagem traz o Thruster como `CMD` (`./bin/thrust ./bin/rails server`), mas o Compose
**sobrescreve** com `bin/rails server -b 0.0.0.0`: na stack quem atende a porta 3000 é o Puma,
sem cache de assets nem compressão do Thruster. Isso não é só preferência — o
`bin/docker-entrypoint` roda `db:prepare` apenas quando os **dois primeiros** argumentos são
`bin/rails server`, e com o `CMD` da imagem o primeiro é `./bin/thrust`. Voltar ao Thruster,
portanto, exige também resolver o `db:prepare` no boot; do jeito que está, ele deixaria de
rodar em silêncio.

## A planilha BIN

O arquivo `.xlsx` precisa trazer estas três abas, com os cabeçalhos declarados em
`BinImport::Template::EXPECTED_HEADERS`:

1. **Faturamento** — faturamento diário (`DIA 01`..`DIA 31` do mês atual e `_M_1` do anterior)
2. **Ativacao** — propostas de credenciamento
3. **Mapa de Clientes BIN** — cadastro e volumes mensais consolidados

As abas são localizadas pelo nome: **abas extras são ignoradas** (o analista costuma anexar
suas próprias planilhas ao arquivo) e a ordem entre elas não é verificada.

Nas colunas vale a mesma lógica, e a regra é uma só: **toda coluna esperada precisa existir,
com o nome exato; o que sobra é ignorado.** A planilha da Fiserv ganha colunas com o tempo —
em 03/09/2026 apareceu `ELEGIBILIDADE D0` — e o importador lê as células pelo nome do
cabeçalho, então coluna a mais não atrapalha. Coluna que falta é erro, e **renomear continua
sendo erro**, porque um renome aparece como falta e sobra ao mesmo tempo. A ordem das colunas
não é verificada, pela mesma razão: a leitura é por nome. No `Mapa de Clientes BIN` só a parte
fixa é literal — as competências das colunas de volume avançam a cada planilha e são validadas
por forma (`VOLUME_HEADER_PATTERN`).

Cada arquivo cobre **um único** `REPORT_ID` e `CANAL`. Arquivo que cumpre o template mas
chega **sem CANAL** não é recusado: a carteira entra sob o canal fictício `SEM CANAL`
(`BinImport::ChannelResolver::FALLBACK_NAME`), com o `REPORT_ID` do arquivo, e cada linha do
Mapa sem canal vira a anomalia `row_without_canal`. Se o `REPORT_ID` já for de um canal
conhecido, o nome dele é mantido — planilha incompleta não renomeia carteira. Mais de um
`CANAL` no mesmo arquivo continua sendo erro. Quando o nome termina em
`_AAAAMMDD.xlsx`, essa data confere a cobertura declarada e pode gerar a anomalia
`cutoff_below_file_date`; sem esse sufixo o import segue, apenas sem a conferência.

### Quando o arquivo é recusado

As mensagens de recusa são escritas para quem tem a planilha na mão, não para quem tem o
código: cada uma diz **o que está errado, onde, e o que fazer** — a aba e a linha da planilha,
o cabeçalho exato que falta ou sobra, os valores que não fecham. A regra vale para as
validações de template, de reconciliação entre abas e de competência.

Na tela de importação o lote que falhou ganha um bloco próprio
(`app/views/import_batches/_failure_report.html.erb`) com a mensagem, os fatos de
identificação — lote, arquivo, data do envio, canal e os 12 primeiros caracteres do checksum —
e um texto pronto para copiar (`ImportBatchesHelper#import_failure_report`), para o operador
reportar ao admin sem transcrever nada errado. A cópia usa a API de área de transferência com
recuo para `execCommand`, porque o portal é servido em HTTP e a API moderna exige contexto
seguro.

**Os arquivos importados ficam guardados** no volume `storage`, por decisão — nada os apaga
depois do import. Cada um traz CNPJ, telefone, endereço e faturamento reais, então quem tem
acesso ao host tem acesso a todos os arquivos já enviados, e o backup (acima) os carrega
junto. O import roda um por vez (`ImportBinFileJob`), então dois envios simultâneos entram
em fila em vez de disputar a consolidação.

### Particularidades da origem

- **Razão social e nome fantasia vêm trocados** nas abas `Faturamento` e `Ativacao`; a aba
  `Mapa de Clientes BIN` vem correta. A inversão está declarada em
  `BinImport::Template::INVERTED_NAME_SHEETS` e é aplicada na leitura.
- **Dias ainda não cobertos chegam como `0`**, não como célula vazia — não dá para distinguir
  "dia sem venda" de "dia fora do arquivo". O dia de corte é o último dia com movimento; quando
  ele fica abaixo do que a data do arquivo sugere, o importador registra a anomalia
  `cutoff_below_file_date` e o ajuste fino fica com o analista (`Operations::AdjustCutoff`).
- **Identificadores numéricos perdem zeros à esquerda** no Excel. `BinImport::Normalizer.ec`,
  `.cnpj` e `.cep` repõem a largura fixa.
- A importação **carrega as três abas em memória** (~96 MB de RSS para 553 ECs). O `Validator`
  faz reconciliação cruzada entre abas, então leitura em streaming exigiria mais de uma passada
  no arquivo. Reavalie se os arquivos crescerem uma ordem de grandeza.
- As quatro tabelas grandes do import (snapshots do Mapa e de faturamento, faturamento diário
  e volumes consolidados) entram por **`COPY`** (`BinImport::BulkCopy`), não por `insert_all!`:
  com ~11 mil linhas cada, o ActiveRecord gastava mais tempo montando o `INSERT` multilinha do
  que o Postgres executando-o.

## Interface

A casca visual (topbar com menu horizontal, trilha e busca global de dados) está descrita em
[`docs/layout.md`](docs/layout.md), com tokens, breakpoints e as decisões de design — entre
elas quando uma listagem é tabela e quando vira grade de cards (recorrente e 3M), a regra de
ordenação das listagens (`ListingSort`) e o modal de lançamentos diários, que mostra as três
últimas competências dia a dia.

Nenhuma página carrega recurso de fora: a CSP está ligada com `default_src :self` e nonce por
requisição no `script-src`, e fonte, ícones e JavaScript são servidos pelo próprio app.
`test/controllers/content_security_policy_test.rb` falha se isso deixar de valer.

## Recriar o banco

```bash
RAILS_ENV=test bin/rails db:rebuild
```

Derruba conexões abertas (os containers se recuperam sozinhos), recria o banco a partir de
`db/structure.sql` e roda o seed (papel do Metabase). `test/db/schema_integrity_test.rb`
garante que o `structure.sql` contém tudo que o app precisa — adapters Solid, views,
partições, extensões — e que o seed cria o papel.

> **Sem `RAILS_ENV=test` ele recria também o banco de development — e é esse que a stack
> serve.** O Compose sobe `web` e `worker` com `RAILS_ENV=production` apontando para
> `fiserv_franchise_intelligence_development`, onde estão os lotes já importados. O banco
> ainda é descartável (o projeto não foi para produção), mas recriá-lo custa reimportar as
> planilhas: rode `bin/db-backup` antes e escolha entre restaurar ou reimportar. No dia a
> dia, mudança de schema entra por `bin/rails db:migrate`.

**O `database.yml` de produção não descreve o que roda aqui.** Ele declara quatro conexões
(`primary`, `cache`, `queue`, `cable`) em bancos separados, como o gerador do Rails escreve; o
Compose sobrescreve as quatro com `DATABASE_URL`, `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL` e
`CABLE_DATABASE_URL` apontando para **o mesmo banco**. Por isso as tabelas dos três adapters
Solid vivem no `structure.sql` do primary, e por isso a `db:rebuild` restringe as tasks ao
`primary` quando o ambiente declara mais de uma config.

O `db:schema:load` do Rails carrega o `structure.sql` chamando `psql` **no host**. Como o
Postgres vive num container e o host pode não ter cliente nenhum instalado, a task detecta a
ausência e manda o arquivo pela entrada padrão do container `db`, gravando na
`ar_internal_metadata` o mesmo `schema_sha1` que o Rails gravaria — sem isso o guarda de
integridade acusa banco desatualizado. Com `psql` no PATH, o caminho continua sendo o do Rails.

## Backup e restauração

```bash
bin/db-backup
```

Grava três arquivos com o mesmo carimbo de data em `BACKUP_DIR` (padrão
`../franchise-storage/backups`, fora do repositório):

| Arquivo | Conteúdo |
| --- | --- |
| `fiserv_<data>.dump` | banco inteiro (`pg_dump -Fc`) |
| `fiserv_<data>_storage.tar.gz` | volume `storage` — as planilhas BIN importadas |
| `fiserv_<data>_metabase.tar.gz` | volume `metabase_data` — perguntas e dashboards |

O Metabase para pelos segundos do `tar`: o H2 é um arquivo aberto pelo processo e a cópia a
quente sairia inconsistente. Arquivos com mais de `BACKUP_KEEP_DAYS` dias (padrão 14) são
apagados ao fim de cada execução. `BACKUP_DIR`, `BACKUP_KEEP_DAYS` e `BACKUP_DB_NAME` (o
banco do dump, padrão `fiserv_franchise_intelligence_development`) saem do `.env`, que o
script lê sozinho.

**Os três arquivos contêm dados reais de cliente.** Ficam fora do repositório e nunca podem
ser versionados, anexados ou enviados para fora da máquina.

Restaurar:

```bash
docker compose exec -T db psql -U postgres -c "CREATE DATABASE fiserv_restore_test"
docker compose exec -T db pg_restore -U postgres -d fiserv_restore_test --no-owner \
  < ../franchise-storage/backups/fiserv_<data>.dump
docker run --rm -v fiserv-franchise-intelligence_storage:/data \
  -v "$(cd ../franchise-storage/backups && pwd)":/backup \
  alpine tar -xzf /backup/fiserv_<data>_storage.tar.gz -C /data
```

O `pg_dump` de um banco **não** carrega papéis do cluster: num cluster novo, rodar
`bin/rails db:seed` depois de restaurar, para recriar o `metabase_ro` e o `GRANT`.

Agendamento diário às 3h30 pelo `launchd`, no arquivo
`~/Library/LaunchAgents/bin.fiserv.franchise-intelligence.db-backup.plist` (não versionado
porque leva caminhos absolutos desta máquina). Carregar é ação manual:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/bin.fiserv.franchise-intelligence.db-backup.plist
launchctl kickstart -p gui/$(id -u)/bin.fiserv.franchise-intelligence.db-backup   # roda agora
launchctl print gui/$(id -u)/bin.fiserv.franchise-intelligence.db-backup | grep "last exit code"
```

**Numa máquina nova, carregar não basta.** Este repositório vive num volume externo
(`/Volumes/macOs`, `Device Location: External`) e agentes do `launchd` não têm permissão para
ler arquivos ali: o job sobe, dispara e morre com `Operation not permitted`. A permissão é
concedida em Ajustes do Sistema → Privacidade e Segurança → **Acesso Total ao Disco**,
adicionando `/bin/bash` (o seletor esconde `/bin`; use Cmd+Shift+G). Ativo desde 07/09/2026,
com o `last exit code = 0` acima como prova.

O plist executa o `bin/db-backup` **da árvore de trabalho**, não de uma cópia fixa: a branch
que estiver aberta é a que roda de madrugada.

A saída vai para `~/Library/Logs/fiserv-db-backup.log`.

O Metabase só é reiniciado ao fim se estava de pé quando o backup começou. Parar o serviço é
decisão de segurança; um backup noturno não pode desfazê-la.

**Último teste de restauração: 2026-09-07**, já com o schema atual — o de depois da remoção
das duas views de auditoria e das três colunas sem uso, e nenhuma migração entrou desde
então (as 21 continuam sendo as mesmas). O dump foi restaurado em `fiserv_restore_test`
e as contagens conferiram com o banco vivo — 556 ECs, 377 empresas, 1.659 snapshots do mapa,
1.375 de faturamento, 17.809 lançamentos diários (mesma soma de `amount`), 4 partições de
`daily_revenues` (três mensais e a `default`), as 5 views materializadas populadas e as 21
migrações. O banco temporário foi apagado ao fim. Repetir o teste — e atualizar esta data —
sempre que o script ou o schema mudarem.

**Risco aceito, por decisão (07/09/2026):** o backup fica no mesmo disco externo do banco.
Protege contra `db:rebuild`, import errado e corrupção lógica; **não** protege contra perda
do disco ou da máquina. Cópia para fora foi avaliada e adiada — não há destino configurado
(nenhum compartilhamento de rede montado, sem Dropbox/Drive/OneDrive), e mandar para fora
exigiria criptografar antes, porque os três arquivos carregam CNPJ e faturamento reais. Cada
conjunto ocupa ~3,7 MB, então volume não é o obstáculo: é a escolha do destino. Reavaliar
antes de o piloto virar operação.

## Views de auditoria

`AuditViews` é dona do DDL das views materializadas de comparação alinhada e do SQL que o
`ReportScope` executa — a regra vive em um lugar só. Depois de mexer nelas, crie uma migração
que chame `AuditViews.recreate!`.

São cinco, todas com leitor: `audit_revenue_by_sub_channel` alimenta `audit_revenue_by_company`,
que alimenta `audit_stalled_companies`; esta e `audit_weekly_revenue` são lidas pelo
`ReportScope`, e `audit_accreditation_earnings` pela página 3M. `AuditViews::SOURCE_TABLES`
lista as tabelas que elas leem e é o que o `ANALYZE` do refresh cobre — o teste
`test/services/audit_views_test.rb` falha se uma view passar a ler tabela fora da lista.

`AuditViews.refresh!` usa `REFRESH ... CONCURRENTLY` fora de transação (e refresh bloqueante
dentro, porque o Postgres recusa o concorrente em transação). Nunca chame dentro de um
`transaction do`.

## Modelo de remuneração

As faixas e alíquotas do modelo da Fiserv vivem **só** em `SubChannelCompensationRules` —
constantes Ruby que geram os `CASE WHEN` da view `audit_accreditation_earnings` (prêmio de
entrada por EC, atualizada no refresh do import) e alimentam o cálculo ao vivo da página 3M
(`ThreeMonthEarningsQuery`, sobre `monthly_volumes_consolidated`). Quem alterar alíquota mexe
lá, cria migração recriando a view e regenera o `structure.sql`. A fonte atual não permite
classificar antecipação automática com segurança. Quando as duas hipóteses divergem, a tela
mostra o intervalo possível sem escolher uma delas.

## Metabase

`MetabaseRole.ensure!` cria o papel somente-leitura `metabase_ro` com `SELECT` restrito às
views de auditoria e redefine a senha toda vez que roda. O papel é do cluster, compartilhado
por todos os bancos, e por isso `METABASE_RO_PASSWORD` é obrigatória fora do ambiente de
teste: sem ela, o seed falha em vez de trocar a senha que o Metabase está usando pela padrão.
O `bin/rails` no host não lê o `.env` — exporte a variável antes de `bin/setup`, `db:seed`
ou `db:rebuild` em development.

## Testes

```bash
bin/rails test
```

`bin/rails test` não inclui os testes de sistema (`test/system`): eles precisam de navegador,
que o host pode não ter. A suíte completa roda na imagem própria de testes, que traz as gems
de desenvolvimento/teste e o Chromium:

```bash
docker compose build test
docker compose run --rm test              # suíte completa: bin/rails db:test:prepare test:all
docker compose run --rm test bin/rails test:system   # só os de sistema
```

O serviço `test` usa o target `test` do Dockerfile e um banco separado. A imagem final de
produção continua sem as gems e os pacotes de navegador usados apenas na verificação.

Os testes de importação usam planilhas sintéticas geradas por `test/support/bin_workbook.rb`;
nenhum dado real de cliente é versionado. Se a planilha de referência da Fiserv estiver em
`../franchise-storage/storage/` (ver acima), o teste correspondente roda também contra ela —
caso contrário é pulado.

As views materializadas só são atualizadas nos testes que as leem, via `refresh_audit_views`.

A suíte roda em processo único (`parallelize(workers: 1)`): com paralelismo por processo os
workers forkados dão segfault no gem `pg` em `connect_start` e o processo pai fica pendurado
no DRb. O mesmo segfault aparece ao rodar `bin/jobs` direto no host — o worker roda em Linux,
onde isso não acontece. Em menos de um minuto de suíte com a máquina livre (medi de 46 s a
3 min 45 s conforme a carga) não compensa perseguir isso; `PARALLEL_WORKERS` continua
sobrescrevendo se quiser testar de novo.
