# Master e MIC passam a ser apagados por marcação, e não por exclusão: os dados ficam, a
# plataforma restaura. A marcação desce do Master para os MICs, ECs e lotes dele, porque a
# planilha seguinte do mesmo REPORT_ID nasce como Master novo e traz os mesmos ECs, o mesmo
# nome de MIC e, às vezes, o mesmo arquivo. Por isso as quatro unicidades globais passam a
# valer só entre os ativos.
class AddSoftDeleteToChannelsAndSubChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :deleted_at, :datetime, comment: "Apagado pelo administrador da organização; só a plataforma restaura"
    add_reference :channels, :deleted_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :sub_channels, :deleted_at, :datetime, comment: "MIC apagado: some das telas e dos totais do Master"
    add_reference :sub_channels, :deleted_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :establishments, :deleted_at, :datetime, comment: "Marcado junto com o Master apagado"
    add_column :import_batches, :deleted_at, :datetime, comment: "Marcado junto com o Master apagado"

    replace_with_partial :channels, :external_id
    replace_with_partial :establishments, :ec
    replace_with_partial :import_batches, :file_checksum
    replace_with_partial :sub_channels, [ :channel_id, :name ]
  end

  private

  # Pelo nome, e não pelas colunas: `establishments.ec` tem também o índice trigram da busca.
  def replace_with_partial(table, columns)
    name = "index_#{table}_on_#{Array(columns).join('_and_')}"
    remove_index table, columns, unique: true, name: name
    add_index table, columns, unique: true, where: "deleted_at IS NULL", name: name
  end
end
