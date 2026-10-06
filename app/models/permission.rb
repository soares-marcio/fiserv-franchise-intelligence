# Catálogo fechado de permissões. Mora aqui, em um lugar só, como as faixas de remuneração
# em SubChannelCompensationRules e as views em ReportScope::VIEWS — quem acrescentar chave
# mexe neste arquivo e numa migration (o CHECK do banco recusa chave desconhecida).
#
# A chave é em inglês, como toda coluna e identificador do projeto; o rótulo é o que aparece
# na tela de convite, em português.
class Permission
  # Uma chave por item do menu de relatórios: quem concede pensa no link que a pessoa vai
  # ver, e uma chave que abrisse os seis juntos dava mais do que a tela de convite mostrava
  # (homologação de 06/10/2026). Cada tela de detalhe pertence ao item de onde se chega.
  REPORTS_REVENUE = "reports_revenue".freeze
  REPORTS_CLOVER = "reports_clover".freeze
  REPORTS_WEEKLY = "reports_weekly".freeze
  REPORTS_THREE_MONTHS = "reports_three_months".freeze
  REPORTS_RECURRING = "reports_recurring".freeze
  REPORTS_INDICATORS = "reports_indicators".freeze
  REPORTS_EXPORT = "reports_export".freeze
  ESTABLISHMENTS_READ = "establishments_read".freeze
  NOTES_READ = "notes_read".freeze
  NOTES_WRITE = "notes_write".freeze
  BATCHES_READ = "batches_read".freeze
  BATCHES_UPLOAD = "batches_upload".freeze
  BATCHES_ADJUST = "batches_adjust".freeze
  BATCHES_DISCARD = "batches_discard".freeze
  BATCHES_APPROVE = "batches_approve".freeze
  METABASE_READ = "metabase_read".freeze
  USERS_INVITE = "users_invite".freeze

  # A ordem é a da tela de convite: leitura, escrita, importação, administração.
  LABELS = {
    REPORTS_REVENUE => "Faturamento",
    REPORTS_CLOVER => "Clover Capital",
    REPORTS_WEEKLY => "Semanal",
    REPORTS_THREE_MONTHS => "Ganhos 3M",
    REPORTS_RECURRING => "Recorrente",
    REPORTS_INDICATORS => "Indicadores",
    REPORTS_EXPORT => "Baixar os relatórios (CSV e planilha)",
    ESTABLISHMENTS_READ => "Ver estabelecimentos",
    NOTES_READ => "Ver anotação do cliente",
    NOTES_WRITE => "Editar anotação do cliente",
    BATCHES_READ => "Ver lotes e baixar a planilha enviada",
    BATCHES_UPLOAD => "Enviar planilha",
    BATCHES_ADJUST => "Reprocessar lote e ajustar o dia de corte",
    BATCHES_DISCARD => "Descartar lote",
    BATCHES_APPROVE => "Aprovar importação em revisão",
    METABASE_READ => "Ver a tela do Metabase",
    USERS_INVITE => "Convidar e administrar usuários"
  }.freeze

  KEYS = LABELS.keys.freeze

  # Na ordem do menu, que é também a ordem de onde a pessoa cai ao entrar.
  REPORT_KEYS = [ REPORTS_REVENUE, REPORTS_CLOVER, REPORTS_WEEKLY, REPORTS_THREE_MONTHS,
    REPORTS_RECURRING, REPORTS_INDICATORS ].freeze

  # O que cada item do menu mostra, na tela de convite: quem concede decide pelo conteúdo,
  # não pelo nome do link.
  DESCRIPTIONS = {
    REPORTS_REVENUE => "Faturamento do mês anterior e do atual por MIC, com a variação no " \
      "mesmo período, e o detalhe de cada MIC até o cliente e o dia.",
    REPORTS_CLOVER => "Ofertas de capital pré-aprovadas por cliente: volume, prazo, taxa e parcela.",
    REPORTS_WEEKLY => "Faturamento dia a dia no calendário, com os clientes que venderam em cada dia.",
    REPORTS_THREE_MONTHS => "Remuneração dos três primeiros meses (M0 a M2) dos credenciamentos " \
      "de cada mês, por MIC.",
    REPORTS_RECURRING => "Ganho recorrente de cada competência por MIC: alíquota da faixa de " \
      "Net MDR sobre débito e crédito.",
    REPORTS_INDICATORS => "Os indicadores mensais do Anexo B por MIC: Adequado, Atenção ou Risco.",
    REPORTS_EXPORT => "Vale nos itens marcados acima e em Estabelecimentos.",
    ESTABLISHMENTS_READ => "Lista de estabelecimentos, ficha do cliente e a busca do topo."
  }.freeze

  # Agrupamento só para a tela; a autorização nunca consulta o grupo, só a chave.
  GROUPS = {
    "Relatórios" => [ *REPORT_KEYS, REPORTS_EXPORT ],
    "Estabelecimentos" => [ ESTABLISHMENTS_READ ],
    "Anotações" => [ NOTES_READ, NOTES_WRITE ],
    "Importação" => [ BATCHES_READ, BATCHES_UPLOAD, BATCHES_ADJUST, BATCHES_DISCARD, BATCHES_APPROVE ],
    # metabase_read continua no catálogo (contas que já a têm seguem válidas) mas fora do
    # formulário: a tela está fechada até haver recorte por organização no Metabase.
    "Administração" => [ USERS_INVITE ]
  }.freeze

  # Chave que só faz sentido ao lado de outra: exportar acontece dentro do relatório, a
  # anotação é lida numa tela de carteira, reprocessar e descartar agem sobre o próprio
  # envio. Uma chave concedida sem a base não abre porta nenhuma, e foi assim que um
  # convite com "Enviar planilha" sozinha não chegou à tela (homologação de 30/09/2026).
  # Cada entrada lista as alternativas: basta uma delas. Quem não está aqui vale sozinha.
  REQUIRES = {
    REPORTS_EXPORT => [ *REPORT_KEYS, ESTABLISHMENTS_READ ],
    NOTES_READ => [ REPORTS_REVENUE, REPORTS_CLOVER, ESTABLISHMENTS_READ ],
    NOTES_WRITE => [ NOTES_READ ],
    BATCHES_ADJUST => [ BATCHES_UPLOAD ],
    BATCHES_DISCARD => [ BATCHES_UPLOAD ]
  }.freeze

  def self.description(key)
    DESCRIPTIONS[key]
  end

  def self.label(key)
    LABELS.fetch(key, key)
  end

  # A base única vem junto: a tela trava "Ver anotação" marcado quando "Editar" está marcado,
  # e caixa travada não viaja no formulário. Com alternativas não há o que escolher pela
  # pessoa — ali nada é acrescentado e a validação continua recusando.
  def self.with_implied(keys)
    KEYS & (keys + keys.flat_map { |key| implied_bases(key) })
  end

  def self.implied_bases(key)
    bases = REQUIRES[key]
    return [] unless bases&.one?

    [ bases.first, *implied_bases(bases.first) ]
  end

  # As chaves do conjunto cuja base falta, com o que falta.
  def self.missing_requirements(keys)
    REQUIRES.filter_map do |key, bases|
      [ key, bases ] if keys.include?(key) && (keys & bases).empty?
    end
  end

  def self.requirement_text(key)
    bases = REQUIRES[key]
    return if bases.nil?
    # Baixar vale em qualquer tela de carteira: listar as sete alternativas não ajuda ninguém.
    return "requer ao menos um item do menu marcado" if key == REPORTS_EXPORT

    "requer #{bases.map { |base| %("#{label(base)}") }.join(' ou ')}"
  end
end
