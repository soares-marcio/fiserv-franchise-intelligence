namespace :db do
  desc "Recria o banco do zero: derruba conexões, carrega db/structure.sql e roda o seed"
  task rebuild: :environment do
    current = ActiveRecord::Base.connection_db_config
    # Em development o db:schema:load também carrega o banco de teste; ele precisa cair junto.
    targets = [ current ]
    targets << ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary") if Rails.env.development?

    # DROP DATABASE recusa se houver conexão aberta (containers web/worker); FORCE as encerra
    # e o supervisor do Solid Queue reinicia os processos sozinho.
    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.establish_connection(current.configuration_hash.merge(database: "postgres"))
    targets.compact.each do |config|
      ActiveRecord::Base.connection.execute(
        "DROP DATABASE IF EXISTS #{ActiveRecord::Base.connection.quote_table_name(config.database)} WITH (FORCE)"
      )
    end
    ActiveRecord::Base.establish_connection(current.configuration_hash)

    # schema:load, não migrate: em banco vazio o migrate carregaria o structure.sql do mesmo
    # jeito, mas ao final o sobrescreveria com um dump — e o arquivo é a fonte da verdade.
    %w[db:create db:schema:load db:seed].each do |name|
      Rake::Task[name].reenable
      Rake::Task[name].invoke
    end

    puts "Recriados #{targets.compact.map(&:database).join(' e ')} a partir de db/structure.sql, com seed aplicado."
  end
end
