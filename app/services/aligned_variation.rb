# Variação alinhada em número, para planilha: a tela usa a versão formatada do helper, mas
# quem abre o arquivo no Excel precisa do valor, não do texto.
module AlignedVariation
  def self.percent(previous, current)
    previous = previous.to_d
    return if previous.zero?

    ((current.to_d / previous - 1) * 100).round(1)
  end
end
