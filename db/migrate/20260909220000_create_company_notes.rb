class CreateCompanyNotes < ActiveRecord::Migration[8.1]
  # Anotação do analista sobre o cliente: uma por CNPJ, substituída a cada gravação. É o
  # primeiro dado do portal que não vem de planilha nenhuma — e, por isso, o primeiro que
  # nenhuma reimportação reconstrói.
  #
  # A ligação é pelo CNPJ e não por FK para companies, por decisão do usuário: id e uuid são
  # regenerados a cada recriação do banco, e o CNPJ não — ele vem da planilha, e o
  # IdentityGuard já recusa import em que um EC mude de CNPJ. É a única identidade do sistema
  # que atravessa um db:rebuild, e é o que torna possível recriar o banco, reimportar as
  # planilhas e restaurar só as anotações: tudo religa sozinho.
  #
  # O preço é não haver integridade referencial. Aqui isso é o comportamento desejado: a
  # anotação sobrevive ao cliente sair de uma planilha e reaparece se ele voltar.
  #
  # Sem COMMENT nas colunas: o comentário é reservado para rastrear origem na planilha, e
  # esta tabela não tem origem lá.
  def change
    create_table :company_notes do |t|
      t.string :cnpj, null: false, limit: 14
      t.timestamps
    end

    # Índice e formato espelham o que companies já garante para a mesma identidade.
    add_index :company_notes, :cnpj, unique: true
    add_check_constraint :company_notes, "cnpj ~ '^[0-9]{14}$'", name: "company_notes_cnpj_format"
  end
end
