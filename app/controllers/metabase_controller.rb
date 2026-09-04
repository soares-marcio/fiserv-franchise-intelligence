class MetabaseController < ApplicationController
  def show
    # Na rede o Metabase é servido pelo Caddy em outra máquina; localhost só vale no host.
    @metabase_url = ENV.fetch("METABASE_URL", "http://localhost:3001")
    @host = ENV.fetch("METABASE_DATA_HOST", "db")
    @port = ENV.fetch("METABASE_DATA_PORT", "5432")
    @database = ActiveRecord::Base.connection.current_database
    @username = MetabaseRole::NAME
    @views = MetabaseRole::VIEWS
  end
end
