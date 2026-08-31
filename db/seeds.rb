# Roda uma vez no primeiro `db:prepare` de um banco novo (produção inclusive) e é idempotente.
# O structure.sql não carrega role nem GRANT, e a migration que cria o metabase_ro não roda em
# banco carregado do arquivo — sem isto, produção nasceria sem acesso do Metabase.
MetabaseRole.ensure!
