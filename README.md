# Fiserv Franchise Intelligence

Auditoria de faturamento da carteira BIN. Importa a planilha mensal que a Fiserv entrega,
consolida o faturamento diário por estabelecimento e compara o mês corrente com o anterior
em períodos de mesma duração.

## Glossário

| Termo | Significado |
| --- | --- |
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

Quando o recorte cobre mais de um canal, usa-se o **menor** dia de corte disponível: comparar
períodos de durações diferentes entre canais distorceria a variação.

Gabaritos oficiais da Fiserv usados como teste de aceitação (ver
`test/services/sub_channel_compensation_rules_test.rb`): carteira de R$ 582.000 (45% débito,
55% crédito) na faixa 0,35–0,39% rende R$ 157,14 + R$ 384,12 = **R$ 541,26**; credenciamento
com meses de 18k/15k/55k paga R$ 50, nada e R$ 39 — total igual à faixa do mês de pico.

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
- PostgreSQL 16 com as extensões `pg_trgm` e `pgvector` (a imagem `pgvector/pgvector:pg16` já traz)

## Setup

```bash
cp .env.example .env          # defina METABASE_RO_PASSWORD e SECRET_KEY_BASE
docker compose up -d db
bin/setup
bin/dev
```

Tudo em contêiner (app, worker, banco e Metabase em `localhost:3001`):

```bash
docker compose up
```

## A planilha BIN

O arquivo `.xlsx` precisa ter exatamente três abas, nesta ordem, com os cabeçalhos exatos
declarados em `BinImport::Template::EXPECTED_HEADERS`:

1. **Faturamento** — faturamento diário (`DIA 01`..`DIA 31` do mês atual e `_M_1` do anterior)
2. **Ativacao** — propostas de credenciamento
3. **Mapa de Clientes BIN** — cadastro e volumes mensais consolidados

Cada arquivo cobre **um único** `REPORT_ID` e `CANAL`. O nome do arquivo deve terminar em
`_AAAAMMDD.xlsx`; essa data é usada para conferir a cobertura declarada.

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

## Interface

A casca visual (header, sidebar, trilha e busca de páginas) está descrita em
[`docs/layout.md`](docs/layout.md), com tokens, breakpoints e as decisões de design.

## Recriar o banco

```bash
bin/rails db:rebuild
```

Derruba conexões abertas (os containers se recuperam sozinhos), recria os bancos de
desenvolvimento e de teste a partir de `db/structure.sql` e roda o seed (papel do Metabase). `test/db/schema_integrity_test.rb` garante que o `structure.sql` contém tudo que
o app precisa — adapters Solid, views, partições, extensões — e que o seed cria o papel.

## Views de auditoria

`AuditViews` é dona do DDL das views materializadas de comparação alinhada e do SQL que o
`ReportScope` executa — a regra vive em um lugar só. Depois de mexer nelas, crie uma migração
que chame `AuditViews.recreate!`.

`AuditViews.refresh!` usa `REFRESH ... CONCURRENTLY` fora de transação (e refresh bloqueante
dentro, porque o Postgres recusa o concorrente em transação). Nunca chame dentro de um
`transaction do`.

## Modelo de remuneração

As faixas e alíquotas do modelo da Fiserv vivem **só** em `SubChannelCompensationRules` —
constantes Ruby que geram os `CASE WHEN` da view `audit_accreditation_earnings` (prêmio de
entrada por EC, atualizada no refresh do import) e alimentam o cálculo ao vivo da página 3M
(`ThreeMonthEarningsQuery`, sobre `monthly_volumes_consolidated`). Quem alterar alíquota mexe
lá, cria migração recriando a view e regenera o `structure.sql`. A tela sempre mostra o prêmio
de credenciamento nas duas hipóteses (com e sem antecipação automática): a classificação vinda
da planilha apenas destaca a provável.

## Metabase

`MetabaseRole.ensure!` cria o papel somente-leitura `metabase_ro` com `SELECT` restrito às
views de auditoria. `METABASE_RO_PASSWORD` é obrigatória em produção.

## Testes

```bash
bin/rails test
```

Os testes de importação usam planilhas sintéticas geradas por `test/support/bin_workbook.rb`;
nenhum dado real de cliente é versionado. Se a planilha de referência da Fiserv estiver no
diretório raiz, o teste correspondente roda também contra ela — caso contrário é pulado.

As views materializadas só são atualizadas nos testes que as leem, via `refresh_audit_views`.

A suíte roda em processo único (`parallelize(workers: 1)`): com paralelismo por processo os
workers forkados dão segfault no gem `pg` em `connect_start` e o processo pai fica pendurado
no DRb. Em ~35s single-process não compensa perseguir isso; `PARALLEL_WORKERS` continua
sobrescrevendo se quiser testar de novo.
