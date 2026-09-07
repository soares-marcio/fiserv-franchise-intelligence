require "shellwords"

# O Postgres roda em container (OrbStack) e o host pode não ter cliente nenhum. O db:schema:load
# do Rails chama psql no host; sem ele, o structure.sql entra pela stdin do container.
DB_COMPOSE_SERVICE = "db".freeze

def psql_on_host?
  system("command -v psql > /dev/null 2>&1")
end

def structure_path
  Rails.root.join("db/structure.sql")
end

def load_structure_in_container!(config)
  user = config.configuration_hash[:username] || "postgres"
  command = "docker compose exec -T #{DB_COMPOSE_SERVICE} psql -U #{user} -d #{config.database} " \
    "--set ON_ERROR_STOP=1 --quiet --no-psqlrc --output /dev/null < #{structure_path.to_s.shellescape}"
  raise "Falha ao carregar #{structure_path} em #{config.database}" unless system(command)

  record_schema_metadata!(config)
end

# O db:schema:load grava o env e o sha1 do arquivo na ar_internal_metadata; sem isso o
# test/db/schema_integrity_test.rb acusa banco desatualizado, e com razão — é o guarda de que
# o structure.sql em disco é o que está carregado.
def record_schema_metadata!(config)
  sha = Digest::SHA1.hexdigest(structure_path.read)
  ActiveRecord::Base.establish_connection(config.configuration_hash)
  ActiveRecord::Base.connection_pool.internal_metadata.create_table_and_set_flags(config.env_name, sha)
end

namespace :db do
  desc "Recria o banco do zero: derruba conexões, carrega db/structure.sql e roda o seed"
  task rebuild: :environment do
    current = ActiveRecord::Base.connection_db_config
    # Em development o db:schema:load também carrega o banco de teste; ele precisa cair junto.
    targets = [ current ]
    targets << ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary") if Rails.env.development?

    # DROP DATABASE recusa se houver conexão aberta (containers web/worker); FORCE as encerra.
    # O worker não sobrevive à janela sem banco: quem o traz de volta é o restart declarado
    # no docker-compose.yml.
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
    # Em produção o database.yml declara cache, queue e cable além do primary, e as tasks sem
    # sufixo iteram as quatro procurando db/cache_structure.sql e companhia — arquivos que não
    # existem, porque as tabelas dos três adapters Solid vivem no structure.sql do primary.
    # Com mais de uma config no ambiente, restringe ao primary; com uma só (dev e teste), a
    # task sem sufixo é necessária, pois é ela que cobre o banco de teste junto.
    suffix = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).size > 1 ? ":#{current.name}" : ""
    Rake::Task["db:create#{suffix}"].reenable
    Rake::Task["db:create#{suffix}"].invoke

    if psql_on_host?
      Rake::Task["db:schema:load#{suffix}"].reenable
      Rake::Task["db:schema:load#{suffix}"].invoke
    else
      targets.compact.each { |config| load_structure_in_container!(config) }
      # O carregamento deixa a conexão no último banco da lista; o seed roda no atual.
      ActiveRecord::Base.establish_connection(current.configuration_hash)
    end

    Rake::Task["db:seed"].reenable
    Rake::Task["db:seed"].invoke

    puts "Recriados #{targets.compact.map(&:database).join(' e ')} a partir de db/structure.sql, com seed aplicado."
  end
end
