class RenameSuperAdminToPlatformAdmin < ActiveRecord::Migration[8.1]
  # O flag muda de significado com as organizações: quem o tem passa a administrar a
  # plataforma (criar organizações e seus administradores) e deixa de ver dado de qualquer
  # carteira. "super" sugere o contrário; o nome novo diz o que o papel faz. Só o nome muda
  # aqui — a semântica troca na fase seguinte, com a suíte inteira acompanhando.
  def change
    rename_column :users, :super_admin, :platform_admin
  end
end
