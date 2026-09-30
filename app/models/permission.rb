# Catálogo fechado de permissões. Mora aqui, em um lugar só, como as faixas de remuneração
# em SubChannelCompensationRules e as views em ReportScope::VIEWS — quem acrescentar chave
# mexe neste arquivo e numa migration (o CHECK do banco recusa chave desconhecida).
#
# A chave é em inglês, como toda coluna e identificador do projeto; o rótulo é o que aparece
# na tela de convite, em português.
class Permission
  REPORTS_READ = "reports_read".freeze
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
    REPORTS_READ => "Ver relatórios",
    REPORTS_EXPORT => "Exportar relatórios",
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

  # Agrupamento só para a tela; a autorização nunca consulta o grupo, só a chave.
  GROUPS = {
    "Relatórios" => [ REPORTS_READ, REPORTS_EXPORT, ESTABLISHMENTS_READ ],
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
    REPORTS_EXPORT => [ REPORTS_READ ],
    NOTES_READ => [ REPORTS_READ, ESTABLISHMENTS_READ ],
    NOTES_WRITE => [ NOTES_READ ],
    BATCHES_ADJUST => [ BATCHES_UPLOAD ],
    BATCHES_DISCARD => [ BATCHES_UPLOAD ]
  }.freeze

  def self.label(key)
    LABELS.fetch(key, key)
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

    "requer #{bases.map { |base| %("#{label(base)}") }.join(' ou ')}"
  end
end
