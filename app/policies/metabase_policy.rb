# A tela mostra host, porta, banco e usuário de conexão do papel somente leitura — e esse
# papel lê as views de auditoria de **todas** as organizações. Enquanto o Metabase não
# recortar por organização, ninguém entra por aqui: nem o administrador da organização,
# nem quem já tinha a chave. O código da tela fica, para o dia em que houver recorte.
class MetabasePolicy < ApplicationPolicy
  def show? = false
end
