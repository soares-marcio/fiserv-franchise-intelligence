class AddSearchIndexesToRevenueLookups < ActiveRecord::Migration[8.1]
  # A busca da listagem por subcanal usa ILIKE '%...%' nestas colunas; sem trigram
  # cada consulta vira sequential scan.
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :revenue_snapshots, :razao_social, using: :gin, opclass: :gin_trgm_ops
    add_index :revenue_snapshots, :nome_fantasia, using: :gin, opclass: :gin_trgm_ops
    add_index :establishments, :ec, using: :gin, opclass: :gin_trgm_ops,
      name: "index_establishments_on_ec_trgm"
    add_index :companies, :cnpj, using: :gin, opclass: :gin_trgm_ops,
      name: "index_companies_on_cnpj_trgm"
  end
end
