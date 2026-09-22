# Liberação de um lote específico a um usuário: é assim que alguém vê um arquivo que não
# enviou. Sem isso, a tela de importação mostra só os próprios envios.
class BatchGrant < ApplicationRecord
  belongs_to :user
  belongs_to :import_batch
  belongs_to :created_by, class_name: "User", optional: true
end
