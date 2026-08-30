class FixSwappedBusinessNames < ActiveRecord::Migration[8.1]
  # As abas Faturamento e Ativacao chegam com razão social e nome fantasia trocados;
  # o importador antigo aplicava a inversão na aba errada (Mapa de Clientes BIN) e não
  # aplicava nas duas que precisavam, gravando os dois campos invertidos nas três tabelas.
  # Lotes manuais nunca passaram por esse caminho e já estão corretos.
  IMPORTED_BATCHES = "import_batch_id IN (SELECT id FROM import_batches WHERE source_filename <> 'manual')".freeze

  def up
    swap_names!
    execute <<~SQL
      UPDATE import_template_columns SET normalization_rule = 'invert_razao_fantasia'
      WHERE sheet_name IN ('Faturamento', 'Ativacao')
        AND source_header IN ('RAZÃO SOCIAL', 'NOME FANTASIA');

      UPDATE import_template_columns SET normalization_rule = 'identity'
      WHERE sheet_name = 'Mapa de Clientes BIN'
        AND source_header IN ('RAZÃO SOCIAL', 'NOME FANTASIA');
    SQL
  end

  def down
    swap_names!
    execute <<~SQL
      UPDATE import_template_columns SET normalization_rule = 'invert_razao_fantasia'
      WHERE sheet_name = 'Mapa de Clientes BIN'
        AND source_header IN ('RAZÃO SOCIAL', 'NOME FANTASIA');

      UPDATE import_template_columns SET normalization_rule = 'identity'
      WHERE sheet_name IN ('Faturamento', 'Ativacao')
        AND source_header IN ('RAZÃO SOCIAL', 'NOME FANTASIA');
    SQL
  end

  private

  def swap_names!
    execute <<~SQL
      UPDATE map_snapshots SET legal_name = trade_name, trade_name = legal_name
      WHERE #{IMPORTED_BATCHES};

      UPDATE revenue_snapshots SET legal_name = trade_name, trade_name = legal_name
      WHERE #{IMPORTED_BATCHES};

      UPDATE activation_proposals SET legal_name = trade_name, trade_name = legal_name;
    SQL
  end
end
