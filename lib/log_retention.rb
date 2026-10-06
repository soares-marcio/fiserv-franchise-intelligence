# O Logger gira o arquivo por dia (web.log.20261005) e nunca apaga o girado. Quem apaga é
# esta limpeza, porque no berry a pasta pertence ao usuário do container: nem o logrotate
# nem o cron do host conseguem remover arquivo de lá (Docker rootless).
#
# 30 dias é decisão de retenção, não de espaço: o log guarda IP, caminho e horário de quem
# acessou.
module LogRetention
  RETENTION = 30.days
  ROTATED = /\.log\.\d{8}\z/

  def self.purge(dir, older_than: RETENTION)
    return unless Dir.exist?(dir)

    Dir.children(dir).each do |name|
      path = File.join(dir, name)
      File.delete(path) if name.match?(ROTATED) && File.mtime(path) < older_than.ago
    end
  end
end
