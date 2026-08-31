class CreateSolidCableAndCacheTables < ActiveRecord::Migration[8.1]
  # Cable e cache apontam para o mesmo banco do app (CABLE_DATABASE_URL/CACHE_DATABASE_URL),
  # então o db:prepare nunca carrega db/cable_schema.rb nem db/cache_schema.rb: esses
  # arquivos só entram em banco separado. Sem a tabela, todo broadcast do Turbo falhava e a
  # tela de importação nunca era avisada. Mesma solução já aplicada ao solid_queue.
  def change
    unless table_exists?(:solid_cable_messages)
      create_table "solid_cable_messages", force: :cascade do |t|
        t.binary "channel", limit: 1024, null: false
        t.binary "payload", limit: 536870912, null: false
        t.datetime "created_at", null: false
        t.integer "channel_hash", limit: 8, null: false
        t.index [ "channel" ], name: "index_solid_cable_messages_on_channel"
        t.index [ "channel_hash" ], name: "index_solid_cable_messages_on_channel_hash"
        t.index [ "created_at" ], name: "index_solid_cable_messages_on_created_at"
      end
    end

    unless table_exists?(:solid_cache_entries)
      create_table "solid_cache_entries", force: :cascade do |t|
        t.binary "key", limit: 1024, null: false
        t.binary "value", limit: 536870912, null: false
        t.datetime "created_at", null: false
        t.integer "key_hash", limit: 8, null: false
        t.integer "byte_size", limit: 4, null: false
        t.index [ "byte_size" ], name: "index_solid_cache_entries_on_byte_size"
        t.index [ "key_hash", "byte_size" ], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
        t.index [ "key_hash" ], name: "index_solid_cache_entries_on_key_hash", unique: true
      end
    end
  end
end
