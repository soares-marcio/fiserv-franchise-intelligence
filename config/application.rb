require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FiservFranchiseIntelligence
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.active_job.queue_adapter = :solid_queue
    config.active_record.schema_format = :sql
    config.time_zone = "America/Sao_Paulo"
    # O único anexo do sistema é a planilha .xlsx do lote, e nenhuma tela pede variante ou
    # prévia. Sem esta linha o padrão :vips tenta carregar o image_processing, removido do
    # Gemfile, e o boot avisa duas vezes. O preço é futuro: se um dia entrar imagem, pedir
    # variante devolverá o arquivo original em silêncio, em vez de falhar — aí a decisão é
    # reverter isto e trazer o gem junto.
    config.active_storage.variant_processor = :disabled
    config.i18n.default_locale = :"pt-BR"
    # Monolíngue por decisão: o pt-BR.yml existe para o Rails formatar data, moeda e
    # percentual em português, não para traduzir a interface — que é escrita em português.
    config.i18n.available_locales = [ :"pt-BR" ]

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
