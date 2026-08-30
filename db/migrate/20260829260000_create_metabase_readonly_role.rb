class CreateMetabaseReadonlyRole < ActiveRecord::Migration[8.1]
  def up
    MetabaseRole.ensure!
  end

  def down
    execute "DROP ROLE IF EXISTS metabase_ro"
  end
end
