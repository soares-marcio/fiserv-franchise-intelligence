class MetabaseController < ApplicationController
  def show
    @host = ENV.fetch("METABASE_DATA_HOST", "db")
    @port = ENV.fetch("METABASE_DATA_PORT", "5432")
    @database = ActiveRecord::Base.connection.current_database
    @username = MetabaseRole::NAME
    @views = MetabaseRole::VIEWS
  end
end
