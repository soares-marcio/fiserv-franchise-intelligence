class MetabaseController < ApplicationController
  def show
    # Na rede o Metabase é servido pelo Caddy; localhost só vale no host. Sem a variável, o
    # serviço está desligado (é o estado do berry desde 09/2026) e a tela diz isso.
    @metabase_url = ENV.fetch("METABASE_URL", "http://localhost:3001")
    @metabase_off = ENV["METABASE_URL"].blank?
    @host = ENV.fetch("METABASE_DATA_HOST", "db")
    @port = ENV.fetch("METABASE_DATA_PORT", "5432")
    @database = ActiveRecord::Base.connection.current_database
    @username = MetabaseRole::NAME
    @views = MetabaseRole::VIEWS
  end
end
