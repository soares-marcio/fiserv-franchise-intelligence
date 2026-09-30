class ScopeCompanyNotesByOrganization < ActiveRecord::Migration[8.1]
  # A anotação era única por CNPJ no portal inteiro: duas organizações com o mesmo cliente
  # leriam e sobrescreveriam a mesma anotação. Passa a ser única por (organização, CNPJ).
  #
  # As anotações que já existem vão para a organização inicial — a mesma que recebeu os
  # Masters na migration anterior. O índice antigo só cai depois de toda anotação ter
  # organização: se alguma ficasse sem, o NOT NULL pararia a migration antes.
  def up
    add_reference :company_notes, :organization, foreign_key: true

    if select_value("SELECT 1 FROM company_notes LIMIT 1")
      id = select_value("SELECT id FROM organizations ORDER BY id LIMIT 1") ||
        select_value("INSERT INTO organizations (name, created_at, updated_at) VALUES (NULL, now(), now()) RETURNING id")
      execute "UPDATE company_notes SET organization_id = #{id} WHERE organization_id IS NULL"
    end

    change_column_null :company_notes, :organization_id, false
    remove_index :company_notes, :cnpj
    add_index :company_notes, %i[organization_id cnpj], unique: true
  end

  # Só volta enquanto houver uma organização: com duas, o mesmo CNPJ pode ter duas
  # anotações e o índice antigo não recria.
  def down
    remove_index :company_notes, %i[organization_id cnpj]
    add_index :company_notes, :cnpj, unique: true
    remove_reference :company_notes, :organization
  end
end
