# Fiserv Franchise Intelligence

## 1. Visão do projeto

O Fiserv Franchise Intelligence será uma aplicação interna de inteligência comercial para apoiar a avaliação e a operação de uma possível franquia ou master franquia Bin/Fiserv.

O sistema utilizará a base de empresas da Receita Federal que já está disponível em containers Podman no servidor `berry`. O Hermes Agent atuará como camada de pesquisa, análise e automação, sem substituir a validação humana, jurídica, financeira ou contratual.

O objetivo do piloto é transformar dados empresariais brutos em uma lista priorizada e explicável de potenciais clientes e territórios, permitindo validar a oportunidade antes de investir em uma estrutura comercial maior.

## 2. Resultado que será entregue

O resultado principal não será apenas um script nem somente uma conversa com o Hermes. Será a evolução da aplicação Django `search-company`, já operacional no `berry`, para um módulo de inteligência Fiserv acessado pelo navegador e acompanhado de rotinas automatizadas de análise.

O piloto deverá entregar:

1. Um painel web executado no `berry` e acessível inicialmente apenas na rede local.
2. Busca e filtros sobre a base de empresas da Receita Federal.
3. Segmentação por município, bairro, CNAE, situação cadastral, porte e tempo de atividade, conforme os campos realmente disponíveis.
4. Uma pontuação de aderência comercial com critérios visíveis e auditáveis.
5. Listas de empresas priorizadas para prospecção.
6. Visão agregada dos territórios e segmentos com maior potencial.
7. Exportação controlada em CSV para uso comercial.
8. Relatórios produzidos pelo Hermes com hipóteses, fontes, limitações e recomendações.
9. Registro do histórico das análises e dos critérios utilizados.
10. Um pacote de continuidade com o último conjunto aprovado de leads, disponível mesmo quando o `berry` estiver indisponível.

Em uma fase posterior, a mesma aplicação poderá ser publicada com domínio próprio por meio de Cloudflare Tunnel, protegida por autenticação e Cloudflare Access.

## 3. Problema que o piloto validará

Antes de assumir premissas financeiras ou comerciais, o piloto deverá responder:

- Quantas empresas ativas e aderentes existem no território analisado?
- Quais CNAEs e regiões concentram os melhores candidatos?
- Quais critérios diferenciam uma empresa prioritária de outra?
- A base existente possui qualidade e atualização suficientes para prospecção?
- Quantos leads úteis podem ser gerados por semana?
- Qual é a taxa de qualificação após validação humana?
- O ganho operacional justifica evoluir o piloto para uma plataforma de produção?

O sistema não deverá afirmar faturamento, volume transacionado, propensão de compra ou elegibilidade à Bin quando esses dados não estiverem presentes em fontes válidas. Nesses casos, apresentará somente inferências identificadas como hipóteses.

## 4. Usuários e usos previstos

### Gestor do projeto

- Avaliar potencial de cidades e segmentos.
- Definir territórios e metas realistas.
- Acompanhar o funil e a qualidade dos leads.
- Produzir evidências para a decisão de avançar ou não com a franquia.

### Operação comercial

- Gerar listas priorizadas.
- Consultar o motivo da pontuação de cada empresa.
- Registrar validação, contato, resultado e próxima ação.
- Exportar somente os dados necessários para a atividade autorizada.

### Hermes Agent

- Gerar análises periódicas a partir de consultas controladas.
- Comparar territórios, segmentos e resultados do funil.
- Produzir resumos executivos e sugestões de experimentos.
- Identificar inconsistências ou lacunas de dados.
- Atualizar relatórios sem alterar silenciosamente os critérios de pontuação.

## 5. Escopo do MVP local

### Incluído

- Reutilização da integração de leitura e do painel Django já existentes no `berry`.
- Inventário do banco, tabelas, campos, índices, atualização e volume.
- Aplicação web responsiva para uso interno.
- Filtros e busca paginada.
- Score inicial baseado em regras determinísticas.
- Explicação do score por empresa.
- Criação e acompanhamento de listas de prospecção.
- Status básicos do funil: `novo`, `em validação`, `qualificado`, `descartado`, `contatado` e `convertido`.
- Exportação CSV com trilha mínima de auditoria.
- Relatórios do Hermes armazenados em arquivos ou banco persistente.
- Backup e procedimento de restauração.

### Fora do MVP

- Disparo automático de mensagens, e-mails ou WhatsApp.
- Compra ou enriquecimento automático de dados pessoais.
- Decisão autônoma de crédito ou elegibilidade.
- Integração com sistemas internos da Fiserv sem autorização e contrato.
- Previsões financeiras apresentadas como fatos.
- Exposição pública direta do banco de dados.
- Automação integral do processo comercial sem revisão humana.

## 6. Arquitetura validada no berry

O diagnóstico de 22 de agosto de 2026 confirmou que o piloto pode aproveitar o ambiente existente. O banco e o painel pertencem ao usuário `soares`; o Hermes roda em outro ambiente Podman rootless, pertencente ao usuário `hermes`. Portanto, o agente não deve receber acesso administrativo direto ao PostgreSQL. A integração recomendada é por uma API interna limitada, mantida pelo `search-company`.

```text
Navegador na rede local
        |
        v
search-company (Django/Gunicorn :8099)
        |
        +---- API da aplicação
        |         |
        |         +---- tabelas operacionais separadas
        |         +---- PostgreSQL pg-cnpj :5432
        |
        +---- Hermes Agent
                  |
                  +---- consultas e ferramentas permitidas
                  +---- relatórios persistidos
```

Componentes previstos:

- **Banco empresarial existente:** PostgreSQL 16.14 com pgvector, container `pg-cnpj`, base `cnpj` com 47 GB e persistência em `/home/soares/cnpj/pgdata`.
- **Banco operacional do projeto:** guarda scores, listas, anotações, status do funil, execuções e auditoria. Deve ficar separado da base original.
- **Backend/API:** será uma evolução do `search-company`, hoje em `/home/soares/search-company`, para aplicar filtros, regras, autorização, paginação e exportação.
- **Frontend web:** o painel Django/Gunicorn já existe e roda pelo serviço `painel-cnpj.service` na porta 8099.
- **Hermes Agent:** está ativo no container `hermes`, imagem `localhost/hermes-custom:ruby40`, com gateway publicado somente em `127.0.0.1:9119` e rede Podman `hermes-net`.
- **systemd:** `pg-cnpj.service`, `painel-cnpj.service` e `hermes.service` estão ativos e configurados para reinício em caso de falha.

No estado diagnosticado, o painel escuta em `0.0.0.0:8099` e o PostgreSQL em `0.0.0.0:5432`/`[::]:5432`. Isso é mais amplo que o necessário. Antes de integrar o Hermes ou usar Cloudflare, o banco deverá ser limitado a loopback ou a uma rede explicitamente autorizada. O painel poderá permanecer na LAN durante o piloto somente com controle de acesso adequado. A abertura por Cloudflare será uma etapa separada.

### 6.1 Continuidade quando o berry estiver indisponível

O Hermes será utilizado somente enquanto o `berry` estiver disponível. Não haverá, no piloto, uma segunda instância do Hermes nem uma réplica integral da base de 47 GB.

Enquanto o `berry` estiver saudável, uma rotina deverá publicar periodicamente um **pacote de continuidade de leads** em um destino independente do servidor. Se o `berry` ficar indisponível, esse pacote será a única funcionalidade de contingência.

```text
berry disponível
    |
    +---- painel, banco e Hermes funcionam normalmente
    |
    +---- gera pacote versionado de leads aprovados
                    |
                    v
          armazenamento independente e criptografado
                    |
                    v
berry indisponível: consulta somente leitura do último pacote válido
```

O fallback não oferecerá:

- execução do Hermes ou troca automática para outro agente;
- pesquisa na base completa da Receita Federal;
- recálculo de score;
- criação, edição ou sincronização de registros do funil;
- exportação de leads ainda não aprovados;
- promessa de dados em tempo real.

Essa limitação é intencional: durante uma indisponibilidade, a prioridade será preservar o acesso seguro aos leads já selecionados, sem criar divergências que precisem ser conciliadas posteriormente.

## 7. Persistência

Todo dado importante deverá ficar fora da camada gravável dos containers.

Devem ser persistidos em volumes ou bind mounts:

- banco operacional;
- configurações sem segredos;
- relatórios e artefatos do Hermes;
- logs necessários para auditoria;
- arquivos exportados;
- backups.

O pacote de continuidade deverá ser armazenado fora do `berry`, criptografado em repouso e protegido por autenticação. O destino concreto será escolhido antes do piloto entre um dispositivo já disponível ou armazenamento remoto controlado; a escolha não altera o formato do pacote.

Imagens dos containers deverão ser reproduzíveis por `Containerfile` ou `Dockerfile`. Atualizações do Hermes deverão ocorrer pela reconstrução da imagem customizada, teste com uma tag versionada e promoção explícita da tag aprovada. Executar `hermes update` apenas dentro de um container descartável não constitui atualização persistente.

## 8. Papel e configuração do Hermes

O Hermes será configurado como analista assistido, não como administrador geral do servidor.

O Hermes não será requisito para consultar leads previamente aprovados. Quando ele ou o `berry` estiver indisponível, o sistema deverá indicar claramente que as análises estão suspensas e informar a data e a versão do último pacote de continuidade disponível.

### Ferramentas recomendadas

1. `company_search`: pesquisa empresas usando parâmetros permitidos.
2. `company_profile`: retorna somente os campos necessários de uma empresa.
3. `territory_summary`: agrega empresas por cidade, CNAE, porte ou situação.
4. `lead_score_explain`: mostra score, critérios e versão da regra.
5. `lead_list_create`: cria uma lista após confirmação humana.
6. `report_generate`: produz relatório em formato padronizado.

Essas ferramentas devem validar parâmetros, limitar quantidade de registros, usar consultas parametrizadas e registrar as execuções relevantes.

### Instruções permanentes do agente

O prompt operacional deverá exigir que o Hermes:

- diferencie fatos, dados ausentes e inferências;
- cite a origem e a data de atualização dos dados;
- não invente contato, faturamento ou volume transacionado;
- não declare que uma empresa será aprovada pela Fiserv;
- não altere score ou registros comerciais sem uma ação autorizada;
- respeite limites de exportação e finalidade de uso;
- solicite revisão humana para decisões comerciais, jurídicas e financeiras;
- produza resultados estruturados e reproduzíveis.

## 9. Modelo inicial de pontuação

O primeiro score deverá ser simples, determinístico e configurável apenas por versão controlada. Um exemplo de composição a validar é:

- situação cadastral ativa;
- CNAE compatível com os segmentos definidos;
- presença no território-alvo;
- porte dentro da faixa comercial escolhida;
- tempo de atividade mínimo;
- existência dos dados cadastrais necessários;
- ausência de sinais cadastrais de descarte definidos pela equipe.

Cada ponto concedido ou retirado deverá aparecer na tela. Pesos reais só serão definidos depois do inventário dos dados e das primeiras validações comerciais. O score mede prioridade de investigação, não probabilidade garantida de venda.

## 10. Segurança, LGPD e governança

- Aplicar minimização de dados e finalidade específica.
- Separar dados públicos cadastrais de anotações comerciais e eventuais dados pessoais.
- Restringir o acesso por usuário e registrar exportações.
- Não incluir segredos nas imagens, repositório, logs ou prompt do agente.
- Manter a base original em leitura durante o piloto.
- Definir retenção e descarte de listas e relatórios.
- Revisar juridicamente o uso da base para prospecção e as obrigações da LGPD antes de qualquer operação comercial em escala.
- Confirmar as condições atuais da franquia diretamente com a Bin/Fiserv; materiais públicos e o template não substituem a COF, o contrato nem assessoria especializada.

## 11. Fases de implementação

### Fase 0 — Descoberta técnica e de negócio — concluída em 22/08/2026

Entregáveis:

- inventário dos containers e da base existente;
- dicionário dos campos úteis;
- avaliação de atualização, cobertura e qualidade;
- definição do território e dos primeiros segmentos;
- critérios de sucesso do piloto;
- lista das condições comerciais que ainda dependem da Fiserv/Bin.

Resultado: a base, o painel, o score e a infraestrutura foram identificados por inspeção somente leitura. É possível formular consultas úteis, mas segurança de rede, usuário de banco somente leitura, atualização e backup ainda precisam ser tratados antes da integração.

### Fase 1 — Adaptar o perfil Fiserv no sistema existente

Entregáveis:

- novo perfil de ICP Fiserv separado do perfil atual de varejo;
- critérios e pesos do score Fiserv versionados;
- consultas reproduzíveis usando a view `estabelecimentos_v`;
- relatório territorial inicial;
- amostra de empresas para validação humana.

Critério de conclusão: a equipe consegue revisar uma amostra e medir quantos resultados são realmente úteis.

### Fase 2 — Evoluir a aplicação web local

Entregáveis:

- módulo Fiserv no painel que já roda no `berry`;
- busca, filtros, perfil da empresa e explicação do score;
- listas e status do funil;
- exportação controlada;
- autenticação local adequada ao piloto;
- geração do pacote de continuidade de leads;
- publicação em destino independente e consulta em modo somente leitura;
- serviços Podman gerenciados pelo systemd.

Critério de conclusão: o fluxo completo funciona pela rede local, sobrevive ao reinício do servidor e o último pacote válido pode ser consultado com o `berry` desligado.

### Fase 3 — Hermes operacional

Entregáveis:

- ferramentas limitadas de consulta e relatório;
- prompts e políticas versionados;
- relatórios recorrentes;
- logs de execução e revisão humana.

Critério de conclusão: o Hermes produz o mesmo tipo de análise de forma repetível, baseada nos dados disponíveis e sem extrapolar suas permissões.

### Fase 4 — Piloto comercial medido

Entregáveis:

- território e segmentos do teste;
- lote controlado de leads;
- métricas de qualificação, contato e conversão;
- registro das causas de descarte;
- relatório de decisão `go`, `ajustar` ou `no-go`.

Critério de conclusão: existem dados suficientes para avaliar utilidade, custo operacional e risco.

### Fase 5 — Acesso remoto seguro

Somente após o piloto local:

- configurar Cloudflare Tunnel sem portas públicas no roteador;
- aplicar Cloudflare Access e identidade autorizada;
- usar HTTPS e domínio próprio;
- revisar headers, sessão, rate limiting, logs e recuperação;
- testar backup, restauração e rollback.

## 12. Métricas do piloto

- empresas disponíveis após os filtros;
- percentual de registros completos;
- precisão percebida do score em amostra revisada;
- percentual de leads qualificados;
- tempo para produzir uma lista útil;
- taxa de contato válido, quando legalmente coletado e verificado;
- conversão por segmento e território;
- motivos de descarte;
- custo de análise e operação por lead qualificado;
- quantidade de correções humanas exigidas nos relatórios do Hermes.

Metas numéricas serão definidas após o inventário da base. Defini-las antes disso criaria falsa precisão.

## 13. Entregáveis concretos do repositório

Ao final do MVP, este repositório deverá conter, no mínimo:

- código da aplicação web e da API;
- testes automatizados;
- migrations do banco operacional;
- definição versionada do score;
- ferramentas disponibilizadas ao Hermes;
- configurações de containers sem segredos;
- unidades ou instruções do systemd;
- procedimento de backup, restauração, atualização e rollback;
- documentação curta de operação;
- decisões arquiteturais e limitações conhecidas.

## 14. Diagnóstico técnico do berry — 22/08/2026

### 14.1 Host e capacidade

| Item | Evidência observada |
|---|---|
| Host | `berry`, Linux 6.8.0-1061-raspi, arquitetura ARM64 |
| CPU | 4 núcleos |
| Memória | 7,8 GiB, com aproximadamente 6,3 GiB disponíveis no momento da inspeção |
| Swap | 4,0 GiB |
| Armazenamento | NVMe de 459 GB, 158 GB usados e 282 GB disponíveis (36% de uso) |

Há capacidade para o piloto, mas consultas sobre dezenas de milhões de linhas devem continuar agregadas no PostgreSQL, com paginação e limites. O Hermes não deve carregar grandes conjuntos de registros no contexto do modelo.

### 14.2 Serviços confirmados

| Serviço | Estado e configuração |
|---|---|
| `pg-cnpj` | Container Podman ativo; imagem `pgvector/pgvector:pg16`; rede do host; limite systemd de 5 GB; `/dev/shm` de 1 GB |
| `painel-cnpj.service` | Django com Gunicorn, dois workers, limite de 512 MB e timeout de 600 segundos; escuta em `0.0.0.0:8099` |
| `hermes.service` | Ativo; container `hermes`; imagem `localhost/hermes-custom:ruby40`; gateway em `127.0.0.1:9119` |

O teste HTTP do painel não retornou em 15 segundos. Isso não prova indisponibilidade: o serviço continuava ativo e a configuração já prevê consultas que podem levar minutos. Ainda assim, latência e health check precisam fazer parte da Fase 2.

### 14.3 Base empresarial confirmada

| Objeto | Estimativa do PostgreSQL | Tamanho total aproximado |
|---|---:|---:|
| `estabelecimentos` | 71.839.926 registros | 35 GB |
| `empresas` | 68.432.394 registros | 12 GB |
| `dominios` | 1.245.916 registros | 115 MB |
| `municipios` | 5.572 registros | 848 kB |
| `cnaes` | 1.359 registros | 376 kB |

A view `estabelecimentos_v` já reúne razão social, nome fantasia, situação, matriz/filial, CNAE, UF, município, endereço, telefones, e-mail, data de início, porte, capital social, maturidade, domínio, site provável, presença digital e `score_prioridade`.

Também já existem índices voltados aos filtros do projeto, incluindo município+CNAE, UF+CNAE, CNAE, zona, domínio, data de início e CNPJ. Isso reduz significativamente o trabalho do MVP.

### 14.4 Competência e atualização

- A estatística do PostgreSQL indica que todos os registros de `estabelecimentos` têm `carga_competencia = 2026-06`.
- Os ZIPs locais estão em `/home/soares/cnpj/zips/2026-06` e foram baixados em 28/07/2026.
- O pipeline existente possui comandos para descobrir competências, baixar e carregar a base.
- Não foi encontrado timer systemd de atualização automática da Receita Federal.

Conclusão: a base está operacional, mas a atualização é manual e está duas competências de calendário atrás na data do diagnóstico. A periodicidade de publicação da fonte deve ser verificada em cada execução; não se deve inferir que uma competência posterior já foi publicada.

### 14.5 Persistência e recuperação

- O banco persiste por bind mount em `/home/soares/cnpj/pgdata`.
- O container pode ser recriado sem perder o banco, desde que esse diretório seja preservado.
- Não foi identificado, no escopo inspecionado, um timer de backup do banco nem um procedimento confirmado de restauração.
- A existência de arquivos `.dump` no host não foi considerada evidência de backup válido desta base, pois conteúdo, data, integridade e restauração não foram confirmados.

Antes do piloto comercial, deve ser criado um backup versionado e deve ser executado ao menos um teste de restauração.

### 14.6 Segurança e separação de responsabilidades

Foram identificados quatro riscos prioritários:

1. O PostgreSQL está configurado com `listen_addresses = '*'` e porta 5432 em todas as interfaces IPv4 e IPv6.
2. O único login específico encontrado, `cnpj`, possui privilégios de superusuário, criação de roles e criação de bancos.
3. Não há role dedicada de leitura para o painel ou para a futura API do Hermes.
4. O painel está em todas as interfaces e ainda precisa de autenticação explícita antes de acesso remoto.

A correção proposta é:

- restringir o PostgreSQL a `127.0.0.1`/socket local quando possível;
- criar uma role sem login administrativo e uma role de aplicação com somente `CONNECT`, `USAGE` e `SELECT` nas views autorizadas;
- manter operações comerciais em tabelas/esquema próprios, com permissões específicas;
- expor ao Hermes somente endpoints limitados da API, nunca a senha de superusuário;
- adicionar autenticação local no piloto e Cloudflare Access na fase remota;
- confirmar firewall e regras de `pg_hba.conf` antes de considerar o banco protegido.

### 14.7 Ativos existentes que serão reutilizados

O repositório `/home/soares/search-company`, atualmente na branch `feature/professional-data-ui` e commit `f074d38` durante o diagnóstico, já possui:

- pipeline de download e carga dos Dados Abertos do CNPJ;
- configuração de ICP em TOML;
- score materializado e filtros comerciais;
- painel Django somente leitura;
- integração com Odoo desabilitada por padrão e protegida por confirmação explícita;
- documentação sobre ingestão, perfil, painel e arquitetura.

O perfil atual é “Varejo — São Paulo capital, prioridade Zona Sul”, com empresas ativas, matrizes, ao menos um ano de atividade, CNAE prefixado por `47` e contato disponível. Ele não deve ser reutilizado silenciosamente como perfil Fiserv: será criado um perfil independente e validado com as premissas comerciais do projeto.

### 14.8 Backlog imediato revisado

Ordem recomendada antes de desenvolver novas telas:

1. Restringir a superfície de rede do PostgreSQL e verificar `pg_hba.conf` e firewall.
2. Criar e testar uma role realmente somente leitura para o painel/API.
3. Definir backup do PostgreSQL e validar uma restauração.
4. Automatizar a verificação de nova competência, mantendo a carga como operação controlada e observável.
5. Criar o perfil `fiserv` sem alterar o ICP atual.
6. Validar o score em uma amostra humana e registrar falso positivo, falso negativo e causa de descarte.
7. Adicionar ao `search-company` uma API interna mínima para as ferramentas do Hermes.
8. Criar autenticação, auditoria de exportação e tabelas do funil.
9. Definir o formato, destino e retenção do pacote de continuidade de leads.
10. Integrar o Hermes à API e testar limites, fontes e explicações.
11. Testar a consulta do último pacote com o `berry` desligado.
12. Só então avaliar Cloudflare Tunnel e Cloudflare Access.

## 15. Critérios revisados para iniciar o piloto

O piloto com dados reais poderá começar quando:

- PostgreSQL não estiver acessível além do necessário;
- aplicação e Hermes não utilizarem a role `cnpj` superusuária;
- backup e restauração estiverem comprovados;
- competência da base aparecer na interface e nos relatórios;
- perfil e score Fiserv estiverem versionados e explicáveis;
- autenticação e auditoria de exportações estiverem ativas;
- o pacote de continuidade estiver criptografado, versionado e acessível sem o `berry`;
- uma amostra inicial tiver sido validada por uma pessoa responsável pelo negócio.

### 15.1 Conteúdo mínimo do pacote de continuidade

O pacote deverá conter somente leads explicitamente aprovados para disponibilização, com minimização de dados. Para cada lead, serão incluídos apenas os campos necessários à consulta comercial:

- CNPJ;
- razão social e nome fantasia;
- município/UF;
- CNAE e segmento;
- canais empresariais de contato aprovados;
- score e motivos do score;
- status existente no momento da publicação;
- competência da base da Receita Federal;
- data de geração do pacote;
- versão do perfil e do score.

O pacote também deverá possuir:

- identificador único e número de versão;
- hash para verificação de integridade;
- quantidade total de leads;
- data de expiração ou alerta de desatualização;
- registro de quem autorizou a publicação;
- política de retenção das versões anteriores.

O formato inicial recomendado é um arquivo CSV criptografado acompanhado de um manifesto JSON assinado ou validado por hash. Uma interface estática protegida poderá ser adicionada depois, caso a consulta direta ao arquivo se mostre insuficiente.

### 15.2 Comportamento em caso de falha

| Situação | Comportamento esperado |
|---|---|
| Apenas Hermes indisponível | Painel e filtros determinísticos continuam; relatórios e análises do agente ficam suspensos |
| `berry` indisponível | Somente o último pacote aprovado fica disponível em modo leitura |
| Pacote ausente, expirado ou inválido | Nenhum lead é apresentado; o usuário recebe um aviso explícito |
| `berry` restaurado | Operação normal retorna; um novo pacote substitui o anterior após validação |

Não haverá edição offline no piloto. Essa decisão evita conflitos, duplicidades e perda de auditoria quando o serviço principal voltar.

## 16. Referência do plano de negócio

O planejamento comercial original permanece em:

`/Users/marcio.soares/Developer/Github/hermes-notes/tecnico/template-plano-negocio-master-franqueado-fiserv.md`

Esse template deve ser usado para estruturar a candidatura e as hipóteses financeiras. O presente documento trata da implementação do sistema de inteligência que dará suporte às análises e à operação.
