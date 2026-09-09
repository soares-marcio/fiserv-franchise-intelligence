# Ofertas pré-aprovadas do Clover Capital, uma linha por CNPJ.
#
# Os quatro campos vêm da aba Mapa de Clientes BIN e já eram importados desde o schema
# inicial, sem tela que os mostrasse. Eles descrevem uma oferta de capital ao cliente:
# quanto, em quantas parcelas, a que taxa.
#
# Por que por CNPJ e não por EC: o Mapa guarda uma linha por EC, mas a oferta é do cliente.
# Medido no lote mais recente da carteira real: 15 CNPJs com oferta em 30 ECs, e exatamente
# 15 combinações distintas de CNPJ e volume — todos os ECs de um CNPJ trazem a mesma oferta.
# `diverging_cnpjs` existe para o dia em que isso deixar de ser verdade: sem ele, a tela
# escolheria uma das ofertas em silêncio.
class PreapprovedOffers
  FIELDS = %w[preapproved_volume preapproved_term preapproved_rate preapproved_installment].freeze

  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  def call
    @call ||= ApplicationRecord.connection.exec_query(sql, "PreapprovedOffers", binds).to_a
  end

  # CNPJs cujos ECs não concordam sobre a oferta. Vazio é o esperado; qualquer coisa aqui é
  # a tela deixando de contar uma parte da verdade, e a página avisa.
  def diverging_cnpjs
    call.filter_map { |row| row["cnpj"] if row["diverging"] }
  end

  # CNPJs cujos ECs discordam da própria razão social. Não é hipótese: no lote mais recente
  # são 3 dos 366 CNPJs, 2 deles com oferta. O caso visto é um EC que traz o nome fantasia
  # na coluna da razão social, e por isso a escolha não pode ser alfabética — MAX() elegia
  # justamente o fantasia. `mode()` fica com o nome que a maioria dos ECs declara.
  def diverging_name_cnpjs
    call.filter_map { |row| row["cnpj"] if row["diverging_name"] }
  end

  private

  def binds
    [ ActiveRecord::Relation::QueryAttribute.new("channel_id", @channel_id,
      ActiveRecord::Type::Integer.new) ]
  end

  # O lote é o mais recente validado que trouxe Mapa — não o mais recente qualquer: um lote
  # só de faturamento zeraria a listagem. Mesmo critério de audit_accreditation_earnings.
  def sql
    <<~SQL
      WITH latest_map_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
        GROUP BY ib.channel_id
      )
      SELECT company.cnpj, company.uuid AS company_uuid,
        note.id AS note_id, note.updated_at AS note_updated_at,
        mode() WITHIN GROUP (ORDER BY snapshot.legal_name) AS legal_name,
        MAX(snapshot.preapproved_volume) AS preapproved_volume,
        MAX(snapshot.preapproved_term) AS preapproved_term,
        MAX(snapshot.preapproved_rate) AS preapproved_rate,
        MAX(snapshot.preapproved_installment) AS preapproved_installment,
        COUNT(DISTINCT establishment.id) AS establishments,
        COUNT(DISTINCT snapshot.legal_name) > 1 AS diverging_name,
        #{diverging_expression} AS diverging
      FROM map_snapshots snapshot
      JOIN latest_map_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      -- Ver o comentário igual em EstablishmentListingQuery: a anotação se liga pelo CNPJ.
      LEFT JOIN company_notes note ON note.cnpj = company.cnpj
      WHERE snapshot.preapproved_volume IS NOT NULL
        AND ($1::bigint IS NULL OR snapshot.channel_id = $1)
      -- Agrupar também pelas colunas da companhia e da anotação não quebra a linha por CNPJ:
      -- cnpj tem índice único nas duas tabelas, então cada grupo já vinha de uma linha só.
      -- O que muda é poder selecionar as colunas delas.
      GROUP BY company.cnpj, company.uuid, note.id, note.updated_at
      ORDER BY MAX(snapshot.preapproved_volume) DESC, company.cnpj
    SQL
  end

  # Um COUNT(DISTINCT) por campo: mais de um valor entre os ECs do CNPJ é divergência.
  # NULL não conta como valor distinto, e é isso que se quer — a parcela vem vazia em toda
  # a carteira e não pode, sozinha, marcar todo mundo como divergente.
  def diverging_expression
    FIELDS.map { |field| "COUNT(DISTINCT snapshot.#{field}) > 1" }.join(" OR ")
  end
end
