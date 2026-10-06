namespace :staging do
  desc "Zera segundo fator, senha provisória, códigos e sessões trazidos da produção"
  task forget_production_secrets: :environment do
    counts = StagingSecrets.forget!
    puts "Segredos da produção apagados: #{counts.map { |name, count| "#{count} #{name}" }.join(', ')}."
  end
end
