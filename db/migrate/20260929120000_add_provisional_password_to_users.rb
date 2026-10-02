class AddProvisionalPasswordToUsers < ActiveRecord::Migration[8.1]
  def change
    # A senha provisória do convite fica visível a quem convidou até a pessoa trocá-la —
    # o flash de poucos segundos não bastava para entregar pessoalmente. Cifrada em repouso
    # (Active Record Encryption, como o otp_secret) e apagada pelo modelo na primeira troca.
    add_column :users, :provisional_password, :text,
      comment: "Senha provisória do convite, cifrada; apagada quando a pessoa troca a senha"
  end
end
