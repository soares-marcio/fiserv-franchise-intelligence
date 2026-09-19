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
| **Prêmio de entrada** | Remuneração por credenciamento, por faixa de faturamento mensal do EC, apurada por **marca d'água**: paga-se em M0 o valor da faixa e, em M1/M2, só a diferença quando a faixa do mês supera o já pago. A coluna da tabela sai da modalidade contratada (`SOLUÇÕES FINANCEIRAS`). Mais R$ 30 de digitalização, uma única vez em M0, para EC com acesso ao app. |
| **Repasse recorrente** | Alíquota (débito e crédito, escolhidas pela faixa de **Net MDR da carteira, sem os ECs Flex**) × volume da modalidade. Vitalício, desde a primeira transação. |
| **Acelerador / redutor** | Mutuamente exclusivos, mês contra mês ("MxM"): crescimento ≥ 20% remunera um % do faturamento **incremental**; queda aplica um % de redução sobre a **Participação do mês** — recorrência mais a parcela do credenciamento. Entre 0% e 19,99% de crescimento não há ajuste, e competência aberta não recebe ajuste nenhum. |
| **Página 3M** | Janela de 3 meses de calendário à escolha do usuário, com débito/crédito por competência (`monthly_volumes`) e o modelo de remuneração aplicado por sub-canal e por EC. |
| **Cliente parado** | Empresa (CNPJ) cuja última venda está a `AuditViews::STALLED_THRESHOLD` dias ou mais do dia de corte — hoje 7. Quem nunca vendeu no mês conta o corte inteiro. Vive só em `audit_stalled_companies`: a tela que o mostrava deu lugar ao Clover Capital. |
| **Oferta pré-aprovada** | Proposta de capital ao cliente, do Clover Capital: volume, prazo e taxa vindos da aba Mapa de Clientes BIN (`VOLUME_PRE_APROVADO`, `PRAZO_PRE_APROVADO`, `TAXA_PRE_APROVADA`). É do CNPJ, não do EC — todos os ECs de um cliente trazem a mesma. `PARCELA_PRE_APROVADA` existe no arquivo e nunca trouxe valor. |

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

- **A linha é o CNPJ, e as contagens também.** Desde 10/09/2026 a listagem mostra **uma
  linha por cliente**, com o faturamento de todos os ECs dele somado: na carteira real, 470
  linhas viraram 302 (medido). Antes a linha era o EC, e as abas e contagens do topo — que
  sempre somaram **CNPJs distintos** — diziam um número diferente do de linhas da tabela.
  No banco o faturamento continua por EC; a soma é da consulta, não do dado. A regra de cada
  coluna da linha agrupada está em `docs/layout.md`.
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

**O portal roda no berry** (`10.0.0.13`, Raspberry Pi com Docker rootless) a partir do corte
descrito em "Levar o sistema para outra máquina" (a data fica lá); o Mac é só
desenvolvimento. Na LAN ele é servido pelo Caddy da mesma máquina (projeto
`~/Composes/fiserv-proxy`, container `fiserv-caddy`), que faz proxy de `http://fiserv.bin`
para `fiserv-web:3000` **pela rede do Compose** (`fiserv-proxy_default`): nenhuma porta do
portal é publicada no host, nem a do Postgres. Isso vem de `docker-compose.berry.yml`,
ativado pelo `COMPOSE_FILE` do `.env` de lá — o `docker-compose.yml` continua o do
desenvolvimento, que publica `3000`/`3001` em `APP_BIND_IP` (padrão `127.0.0.1`) e o Postgres
em `127.0.0.1:5432`. O DNS local (Pi-hole, no próprio berry) resolve `fiserv.bin` para ele.
Em produção o app aceita apenas `Host: fiserv.bin` e `localhost` (`RAILS_HOSTS` acrescenta
outros); `force_ssl` fica desligado enquanto o Caddy servir HTTP puro — liga-se quando ele
passar a terminar TLS.

O clone fica em `/home/soares/repos/franchise-intelligence`, ao lado dos outros projetos do
berry; dados reais (backups, logs) em `/home/soares/fiserv-storage/`, fora do clone. O
berry divide a máquina com o `lottery-app` — redes, volumes e portas são por projeto, e só
o Caddy é compartilhado.

**Cadeia de deploy**, depois do merge na `main`:

```bash
ssh berry ~/repos/franchise-intelligence/bin/deploy
```

O `bin/deploy` faz `git pull --ff-only`, `bin/db-backup`, `docker compose up -d --build web
worker` e confere `http://fiserv.bin/up` pelo próprio berry. A migração corre no
`db:prepare` do entrypoint quando o `web` sobe — por isso o backup vem antes. Não há
rollback automático: as imagens anteriores ficam, e voltar é `git checkout <sha>` seguido de
`docker compose up -d --build web worker`.

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
| `fiserv_<data>_storage.tar.gz` | volume `storage` — as planilhas BIN e os anexos das anotações |
| `fiserv_<data>_metabase.tar.gz` | volume `metabase_data` — perguntas e dashboards |

O Metabase para pelos segundos do `tar`: o H2 é um arquivo aberto pelo processo e a cópia a
quente sairia inconsistente. Onde o volume `metabase_data` não existe (o berry, enquanto o
Metabase estiver desligado), o script avisa e pula esse arquivo em vez de criar um volume
vazio para arquivá-lo. Arquivos com mais de `BACKUP_KEEP_DAYS` dias (padrão 14) são
apagados ao fim de cada execução. `BACKUP_DIR`, `BACKUP_KEEP_DAYS` e `BACKUP_DB_NAME` (o
banco do dump, padrão `fiserv_franchise_intelligence_development`) saem do `.env`, que o
script lê sozinho.

**Onde roda, desde a migração para o berry:** no cron do `soares`, às 3h30, gravando em
`/home/soares/fiserv-storage/backups` (o `DOCKER_HOST` do Docker rootless já está definido
no topo do crontab):

```
30 3 * * * cd /home/soares/repos/franchise-intelligence && bin/db-backup >> /home/soares/fiserv-storage/logs/db-backup.log 2>&1
```

E o Mac **puxa uma cópia** às 4h00 pelo `launchd`
(`~/Library/LaunchAgents/bin.fiserv.franchise-intelligence.backup-sync.plist`, não versionado
porque leva caminhos absolutos):

```bash
rsync -a --delete -e "ssh -o BatchMode=yes" berry:fiserv-storage/backups/ \
  /Volumes/macOs/Developer/Sites/GitHub/fiserv/franchise-storage/backups/berry/
```

É espelho: a retenção é a do berry. Com isso o backup passa a viver em duas máquinas — o
risco aceito em 07/09/2026 (backup no mesmo disco do banco) deixa de valer.

**Os três arquivos contêm dados reais de cliente.** Saem com modo 600 (só o dono lê), ficam
fora do repositório e nunca podem ser versionados, anexados ou enviados para fora da máquina.

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

### Levar o sistema para outra máquina

**Migração roda sozinha.** O `bin/docker-entrypoint` chama `db:prepare` quando o comando
começa com `bin/rails server`, que é o `command` do serviço `web` — banco novo nasce do
`db/structure.sql` com o seed aplicado, e banco existente recebe só as migrations pendentes.
O `worker` (`bin/jobs`) não migra, de propósito: só um processo deve fazer isso, e ele espera
o healthcheck do `web`, que só responde depois do `db:prepare`.

Com o código apenas, `docker compose up -d` basta. **Levando os dados junto, são três coisas,
e a terceira é a que surpreende:**

| O quê | Por quê |
| --- | --- |
| `fiserv_<data>.dump` | o banco |
| `fiserv_<data>_storage.tar.gz` | as planilhas e os anexos das anotações vivem no disco, não no banco |
| o **mesmo** `SECRET_KEY_BASE` | verificado: o `sgid` que o Action Text grava dentro do HTML da anotação é assinado com ele |

Sobre o terceiro: com outro `SECRET_KEY_BASE`, a anotação chega com o texto intacto e **os
anexos somem** — o `<action-text-attachment sgid="…">` deixa de resolver, porque a assinatura
não passa. Isso não vale para as planilhas importadas, que são referenciadas por chave
estrangeira comum; é uma consequência dos anexos das anotações.

Um detalhe que ajuda no caminho contrário: a anotação em si se liga ao **CNPJ**, não a
`companies.id`. Dá para reimportar as planilhas num banco novo e restaurar só
`company_notes`, `action_text_rich_texts` e as tabelas do Active Storage que tudo religa
sozinho — desde que o `SECRET_KEY_BASE` seja o mesmo, pelo motivo acima.

**Roteiro da migração Mac → berry** (executado em **18/09/2026**, ~15 min de portal fora):

1. No berry, sem tocar no que está no ar: `git clone` em `~/repos/franchise-intelligence`,
   `.env` com o **mesmo** `SECRET_KEY_BASE` e `METABASE_RO_PASSWORD` (copiados por `scp`,
   nunca por chat ou log), `COMPOSE_FILE=docker-compose.yml:docker-compose.berry.yml`,
   `BACKUP_DIR=/home/soares/fiserv-storage/backups`; `docker compose config` sem nenhuma
   `ports:`; `docker compose build web worker` (211 s no primeiro build; a segunda passagem
   pelo Dockerfile, do `worker`, é replay de cache e custou só a exportação da imagem).
2. No Mac: `docker compose stop web worker`, `bin/db-backup`, contagens de referência
   (`establishments`, `companies`, `map_snapshots`, `revenue_snapshots`, `daily_revenues` e
   a soma de `amount`, `import_batches`, `company_notes`, `active_storage_blobs`,
   `period_coverages`).
3. `scp` do dump e do `_storage.tar.gz` para `berry:~/fiserv-storage/backups/`.
4. No berry: `docker compose up -d db` → `CREATE ROLE metabase_ro NOLOGIN` **antes** do
   `pg_restore` (o dump carrega os `GRANT` ao papel, e com `--exit-on-error` o restore para
   no primeiro deles; as permissões e o `REFRESH` das views rodam em passadas próprias, depois
   de tabelas, dados e índices — foi o que sobrou para reaplicar em 18/09) → `pg_restore
   --no-owner` → `docker compose run --rm web bin/rails db:seed` (dá LOGIN e senha ao papel;
   `db:prepare` num banco povoado não roda o seed) → `tar -xzf` do `storage` no volume →
   `docker compose up -d`.
5. Conferir no berry: contagens iguais, 5 views populadas, `metabase_ro` lendo a view de
   credenciamento, `/up` de dentro do container.
6. Caddyfile: `fiserv.bin → fiserv-web:3000`; `caddy reload` sem derrubar.
7. Conferir pela rede e do Mac; no Mac, `docker compose down` (volumes ficam 14 dias),
   `APP_BIND_IP` fora do `.env`, `launchd` trocado pelo `backup-sync`.

**Enquanto a stack roda no Mac** (até o corte para o berry), o agendamento é pelo
`launchd` (`bin.fiserv.franchise-intelligence.db-backup.plist`, às 3h30). Depois do corte, o
que fica dele é o `backup-sync` acima, e o que se aprendeu vale para qualquer agente do
`launchd` que toque este repositório:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/bin.fiserv.franchise-intelligence.backup-sync.plist
launchctl kickstart -p gui/$(id -u)/bin.fiserv.franchise-intelligence.backup-sync   # roda agora
launchctl print gui/$(id -u)/bin.fiserv.franchise-intelligence.backup-sync | grep "last exit code"
```

**Carregar não basta.** Este repositório vive num volume externo (`/Volumes/macOs`,
`Device Location: External`) e agentes do `launchd` não têm permissão para ler ou gravar
ali: o job sobe, dispara e morre com `Operation not permitted`. A permissão é concedida em
Ajustes do Sistema → Privacidade e Segurança → **Acesso Total ao Disco**, adicionando
`/bin/bash` (o seletor esconde `/bin`; use Cmd+Shift+G). Ativa desde 07/09/2026. A saída
vai para `~/Library/Logs/fiserv-backup-sync.log`.

O Metabase só é reiniciado ao fim do `bin/db-backup` se estava de pé quando o backup
começou. Parar o serviço é decisão de segurança; um backup noturno não pode desfazê-la.

**Último teste de restauração: 2026-09-18** — o próprio corte para o berry: dump e volume
`storage` do Mac restaurados num cluster vazio e conferidos contra as contagens de referência
(964 ECs, 717 empresas, 3.744 snapshots do mapa, 2.914 de faturamento, 34.794 lançamentos
diários com a mesma soma de `amount`, 45.779 volumes mensais, 7 lotes, 21 anotações, 7 blobs,
5 coberturas), as 5 views materializadas populadas, o papel `metabase_ro` lendo a view de
credenciamento e negado nas tabelas base, e os 8 arquivos do `storage` com dono `1000:1000`.
O teste anterior (2026-09-07) restaurou em `fiserv_restore_test` no Mac. Repetir o teste — e
atualizar esta data — sempre que o script ou o schema mudarem.

**Risco aceito em 07/09/2026, encerrado com a migração:** o backup ficava no mesmo disco
do banco — protegia contra `db:rebuild`, import errado e corrupção lógica, não contra perda
do disco ou da máquina. Com o banco no berry e o `rsync` diário para o Mac, o backup vive em
duas máquinas da mesma rede. Continua **dentro** da LAN por decisão: mandar para fora
exigiria criptografar antes, porque os arquivos carregam CNPJ e faturamento reais.

## Views de auditoria

`AuditViews` é dona do DDL das views materializadas de comparação alinhada e do SQL que o
`ReportScope` executa — a regra vive em um lugar só. Depois de mexer nelas, crie uma migração
que chame `AuditViews.recreate!`.

São cinco. `audit_revenue_by_sub_channel` alimenta `audit_revenue_by_company`, que alimenta
`audit_stalled_companies`, e `audit_accreditation_earnings` é lida pela página 3M.

**Duas estão sem leitor de tela:** `audit_weekly_revenue` perdeu o dela quando a tela semanal
virou calendário, e `audit_stalled_companies` quando a página de clientes parados deu lugar ao
Clover Capital. `ReportScope#stalled_companies` continua existindo e é exercitado pelos testes,
mas nenhuma tela o chama. Removê-las exige migração, e não se verificou se o Metabase as lê —
por isso ficam. `AuditViews::SOURCE_TABLES`
lista as tabelas que elas leem e é o que o `ANALYZE` do refresh cobre — o teste
`test/services/audit_views_test.rb` falha se uma view passar a ler tabela fora da lista.

`AuditViews.refresh!` usa `REFRESH ... CONCURRENTLY` fora de transação (e refresh bloqueante
dentro, porque o Postgres recusa o concorrente em transação). Nunca chame dentro de um
`transaction do`.

## Modelo de remuneração

A fonte é o **Anexo C – Participação do Franqueado**, da Circular de Oferta de Franquia
(v1.2023, vigência 01/08/2023). Ele compõe a Participação de quatro fatores: credenciamento,
recorrência, deduções de performance e campanhas.

As faixas e alíquotas vivem **só** em `SubChannelCompensationRules` — constantes Ruby que
geram os `CASE WHEN` da view `audit_accreditation_earnings` e alimentam o cálculo ao vivo da
página 3M (`ThreeMonthEarningsQuery`) e do recorrente (`RecurringEarningsQuery`). Quem alterar
alíquota mexe lá, cria migração recriando a view e regenera o `structure.sql`.

**A modalidade de antecipação é `SOLUÇÕES FINANCEIRAS`.** O contrato chama a coluna "C" de
"com auto/flex" — modalidade **contratada** — e trata a antecipação **realizada** como base de
outra remuneração (1.1.2-B). São fatos diferentes, e foi tratar um pelo outro que tornou a
classificação impossível até 09/2026. `Auto`, `Flex` e `Combo` usam a coluna C; `NÃO` usa a B;
ausente fica indefinido e a tela volta a mostrar o intervalo. Medido em 16/09/2026: 567 ECs
classificados, nenhum vazio — Auto 502, NÃO 61, Flex 2, Combo 2. Fica registrado o risco: se a
Fiserv apurar pela antecipação realizada, 251 dos 502 "Auto" mudariam de coluna.

**O redutor incide sobre a Participação do mês**, não só sobre a linha recorrente (1.1.3) —
por isso o prêmio é apurado mês a mês e despivotado para a competência de calendário. A base
é credenciamento (parcela do mês mais digitalização) + recorrência, e cobre a Participação
do contrato: o fator "deduções de performance" é o próprio redutor (1.1.3), e a única
campanha viva é a do APP BIN — com grande probabilidade, os R$ 30 já dentro da base.

**A fronteira de R$ 20.000 está resolvida pelo próprio contrato.** As duas simulações do Anexo
C discordam entre si: a Simulação 1 lê R$ 20.000 na faixa 20.000–24.999,99 (C = R$ 300, a
tabela literal) e a Simulação 2 lê na faixa de baixo (B = R$ 50). A tabela concorda com a
primeira, que fecha no centavo nos três meses. As duas simulações estão em
`sub_channel_compensation_rules_test.rb` como gabarito.

### O que o contrato prevê e o portal não apura

- **Repasse sobre antecipação (1.1.2-B):** no extrato, 11% (automática) ou 7% (eventual)
  sobre o *spread* — valor antecipado menos valor líquido creditado (ver "Como a Fiserv
  compõe o extrato mensal"). A planilha traz o **volume** (`VOLUME DE ANTECIPAÇÃO`, que bate
  no centavo com o extrato) e **não traz o líquido, a taxa nem o prazo** de cada operação.
  Para apurar, seria preciso pedir à Fiserv o valor líquido (ou taxa e prazo) por EC e mês.
- **Recredenciamento em 12 meses (1.1):** um EC que sai da base só volta a ser credenciamento
  novo depois de 12 meses. O portal paga sempre que `DATA DE CREDENCIAMENTO` cai na janela.
  Medido em 16/09/2026: nenhum EC teve `accredited_on` alterado entre lotes, então a regra não
  tem ocorrência — mas 113 dos 567 ECs têm data de suspensão, e pode ocorrer.
- **Campanhas futuras** (1.1.4): provisórias e com regulamento próprio, não têm como ser
  apuradas antes de existirem. Das atuais, o contrato revoga todas menos a do **APP BIN** —
  confirmada no extrato como a aba "Campanha APP", R$ 30 por CNPJ: os R$ 30 de digitalização
  não são uma faixa permanente da tabela, e sim a campanha sobrevivente, já dentro da base.
- **Pix, MDR Flex e Clover Capital** aparecem no extrato e não no Anexo C nem no arquivo —
  fórmulas e lacunas na seção seguinte.

### Indicadores do Anexo B

O **Anexo B – Indicadores** do Contrato de Micro Franquia (p. 35) fixa sete indicadores
mensais, cada um com três leituras — Adequado, Atenção e Risco. Eles condicionam a
Participação (Definição 26: paga "mediante o cumprimento dos Indicadores") e, mantidos em
descumprimento por 60 dias ou mais, dão à Franqueadora o direito de rescindir (cláusula
12.2, xx). As faixas vivem só em `SubChannelIndicatorRules`; a apuração em
`SubChannelIndicatorsQuery`; a tela em `/reports/indicators`, um card por MIC.

| Indicador | Numerador | Base | Adequado · Atenção · Risco |
| --- | --- | --- | --- |
| Qualidade das indicações | propostas `Credit Declined` | propostas do mês pela `DATA DA PROPOSTA`, no status mais recente de cada `NR DA PROPOSTA`; pendentes (`Pending QC`) contam na base | ≤ 10% · 10,01–25% · ≥ 25,01% |
| Credenciamentos | ECs com `DATA DE CREDENCIAMENTO` no mês, no último Mapa (= "ECs no M0" da tela 3M) | — | ≥ 10 · 5–9 · ≤ 4 |
| Volume transacional | ECs com débito + crédito do mês acima de R$ 10.000 | base do mês | ≥ 92% · 88,01–91,99% · ≤ 88% |
| Descredenciamento | ECs com `DATA DE SUSPENSÃO` no mês | base do mês | ≤ 2% · 2,01–5% · ≥ 5,01% |
| ECs sem transação | ECs com `ATIVO NO MÊS ATUAL?` = não | base do mês | ≤ 5% · 5,01–10% · ≥ 10,01% |
| Índice de reclamações | — | — | **não apurável**: o arquivo não traz reclamações |
| Ordens canceladas | — | — | **não apurável**: sem coluna, e as faixas do anexo se sobrepõem |

Leituras que o texto do anexo obriga a declarar:

- **A base do mês** são os ECs do Mapa daquela competência (`current_period` igual ao mês;
  o último lote, se houve vários) que não estavam suspensos antes de ela começar. Sem Mapa
  da competência, os três indicadores que dependem dela ficam **sem leitura** — não se
  empresta a base de outro mês, cujo `ATIVO NO MÊS ATUAL?` descreve outro mês. Com os
  arquivos semanais o histórico se constrói sozinho. Medido em 17/09/2026, MIC GOIANIA 4 em
  agosto: 227 ECs no arquivo, 210 na base.
- **"Atividade dos Estabelecimentos" está escrito invertido**: "percentual com pelo menos
  uma transação", com Adequado ≤ 5%. Ao pé da letra, uma carteira toda ativa seria Risco. O
  portal lê a fração **sem** transação, e a coluna se chama assim na tela.
- **Qualidade é "percentual de pedidos rejeitados"**: recusadas sobre os pedidos do mês, com
  as pendentes na base — um pedido pendente é pedido, e ainda pode ser recusado. A leitura
  sobre decididas daria mais alto; a fração e as pendentes ficam no title da célula.
- **Competência aberta mostra o valor e não a leitura**: um mês pela metade credencia e
  transaciona menos por não ter terminado.
- **A sequência em Risco** conta, do último mês fechado com leitura para trás, os meses
  fechados seguidos em Risco; dois alcançam os 60 dias. O anexo não define "descumprir" —
  o portal conta só o Risco, nunca a Atenção. Mês sem leitura interrompe a contagem.
- **`ATIVO NO MÊS ATUAL?` é a declaração da própria Fiserv** e concorda com o volume do mês
  em 567 de 567 ECs no lote de setembro (medido em 17/09/2026).

### Como a Fiserv compõe o extrato mensal

Conferido com o extrato de agosto/2026 do MIC GOIANIA 4 (`NETO – MIC … .xlsx`, 9 abas),
cruzado com o banco por CNPJ em 17/09/2026. O `Consolidado` soma as abas —
`MDR + Antecipação + MDR Flex + Faturamento 3M + Pix + Clover Capital + Campanha APP
± Redutor/Acelerador` — mais a diferença de apurações anteriores. O extrato é de uma
**competência** (Base MDR com `Período = 2026-08` e o faturamento de agosto; um EC com
boarding em 04/08 já entra como M0) e é **pago no mês seguinte**: quando se diz que a
campanha APP "é feita no M0 e paga no M1", M1 é o caixa, não a competência — vocabulário
alinhado com o usuário em 17/09/2026.

| Aba | Como a Fiserv calcula | Portal |
| --- | --- | --- |
| Base MDR · Repasse MDR | `MDR líquido = MDR STD − interchange`, por EC e produto; `% net MDR da carteira = Σ MDR líquido ÷ Σ faturamento` escolhe a faixa; repasse = faturamento crédito × alíquota crédito + faturamento débito × alíquota débito | igual, desde que o Net MDR venha do **arquivo do mês seguinte** (abaixo). Agosto/2026: R$ 359,81 contra R$ 359,78 |
| Faturamento 3M | `diferença a receber = valor da faixa do mês − valor já recebido` (marca d'água), coluna B ou C pela modalidade; só ECs com parcela > 0 no mês | igual: 13 de 13 CNPJs, R$ 5.106 |
| Campanha APP | R$ 30 **por CNPJ**, no mês do primeiro acesso ao app — pagou M1 também | por CNPJ, no mês do primeiro acesso observado, dentro de M0–M2; sem transição observada, M0 (abaixo) |
| Antecipação | `spread = valor antecipado − valor líquido creditado`; repasse = spread × 11% (tipo 2, automática) ou 7% (tipo 1, eventual) | não apurável: o arquivo traz o volume (bate no centavo em 100 CNPJs), não o líquido, a taxa nem o prazo |
| Pix | 15% da receita Pix do mês + R$ 30 por CNPJ com conta aberta no mês | não apurável: sem coluna de Pix |
| MDR Flex · Clover Capital | abas vazias em agosto/2026 | alíquota desconhecida |
| Δ Faturamento | mês ÷ mês anterior − 1, sobre o faturamento do extrato | igual (9,21%) |

**O NET MDR do Mapa é o MDR líquido realizado do mês anterior ao do arquivo.** O arquivo de
setembro reproduz o realizado de agosto do extrato em 110 de 112 CNPJs (|Δ| < 0,01 pp); os
de agosto, idênticos entre si, **não** são o realizado de agosto (0,04 pp de mediana) — que
carregam julho é inferência da regra, a confirmar com o extrato de julho; ECs sem mês
anterior fechado vêm sem a coluna. O primeiro arquivo do mês ainda assenta (97 de 112 em
03/09); do segundo em diante está fechado — o portal usa o último arquivo do mês, e nos
primeiros dias após a virada o "fechado" pode estar ligeiramente adiantado, corrigindo-se
no arquivo seguinte. Por isso o recorrente ancora a competência P no **último arquivo de
P + 1** — sem ele, usa o próprio arquivo e marca ‡ (provisório); antes do primeiro arquivo,
o mais antigo, com †. Ancorar no arquivo de P custou um repasse zerado em agosto/2026:
0,2489% (arquivo de agosto) contra 0,2947% (realizado), com o degrau da faixa em 0,25%.

**A campanha APP no portal.** A coluna `ULTIMO ACESSO NO APP` sobrescreve; o primeiro
acesso só é conhecido quando um lote mostrou o CNPJ sem acesso antes. Sem essa transição —
CNPJs anteriores ao primeiro arquivo importado —, a campanha cai em M0: sem isso a view
pagaria 39 CNPJs em agosto/2026 no GOIANIA 4, e 20 deles a Fiserv já tinha pago antes.
Resultado em agosto: 12 dos 21 CNPJs do extrato; 7 caem em julho (indistinguíveis dos 20) e
2 em setembro (a coluna atrasa ~3 dias na virada do mês). Com os arquivos semanais a
transição passa a ser vista, e a regra se corrige sozinha. A transição é lida na ordem dos
lotes (`import_batch_id`): um arquivo antigo importado depois não conta como "visto sem
acesso", e a campanha fica em M0 — o lado seguro. A digitalização também deixou de exigir
volume em M0: a aba "Campanha APP" não tem coluna de faturamento, e a Fiserv pagou os 21
CNPJs sem olhar o volume.

## Metabase


`MetabaseRole.ensure!` cria o papel somente-leitura `metabase_ro` com `SELECT` restrito às
views de auditoria e redefine a senha toda vez que roda. O papel é do cluster, compartilhado
por todos os bancos, e por isso `METABASE_RO_PASSWORD` é obrigatória fora do ambiente de
teste: sem ela, o seed falha em vez de trocar a senha que o Metabase está usando pela padrão.
O `bin/rails` no host não lê o `.env` — exporte a variável antes de `bin/setup`, `db:seed`
ou `db:rebuild` em development.

### Build futuro: Metabase no berry

O Metabase **não sobe no berry** por decisão de 18/09/2026: ele nunca passou pelo setup
inicial, o volume dele tinha 7 MB sem pergunta nem dashboard de valor, e é o serviço mais
pesado da stack (JVM). No `docker-compose.berry.yml` ele está atrás do profile `metabase`;
a página `/metabase` do portal continua existindo e avisa que o serviço está desligado. O
papel `metabase_ro` continua sendo criado pelo seed — `METABASE_RO_PASSWORD` segue
obrigatória — para o dia em que ligar. Para ligar:

1. `docker compose --profile metabase up -d metabase` (o volume `metabase_data` nasce vazio;
   para trazer o do Mac, restaurar `fiserv_<data>_metabase.tar.gz` nele com o `tar -xzf` da
   seção de restauração, **antes** de subir).
2. Caddyfile do `fiserv-proxy`: `http://fiserv-metabase.bin { reverse_proxy fiserv-metabase:3000 }`
   e `docker exec fiserv-caddy caddy reload --config /etc/caddy/Caddyfile`. O Pi-hole já
   resolve o nome.
3. `.env` do berry: `METABASE_URL=http://fiserv-metabase.bin` e `docker compose restart web`
   (a variável é lida pelo `web`).
4. Concluir o setup inicial **com senha** antes de deixar o nome na rede — a ressalva de
   segurança do CLAUDE.md ("Controle de acesso") vale a partir do momento em que ele sobe.
   Fonte de dados: host `db`, porta `5432`, banco `fiserv_franchise_intelligence_development`,
   usuário `metabase_ro`.
5. `bin/db-backup` passa a gerar o terceiro arquivo sozinho, porque o volume existe.

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
