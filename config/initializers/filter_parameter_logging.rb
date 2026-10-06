# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# O código do segundo fator (autenticador ou recuperação) chega como `code`, que nenhum dos
# padrões acima pega. Âncora pelo mesmo motivo de :ec e :q — `cnae_code` é dado público.
Rails.application.config.filter_parameters += [ /\Acode\z/ ]

# Dados pessoais e cadastrais das planilhas BIN não podem vazar para o log.
# :ec e :q usam regex ancorada porque o match parcial pegaria "record", "query", etc.
# :q é o termo de busca, que aceita CNPJ.
Rails.application.config.filter_parameters += [
  :cnpj, :cpf, :work_phone, :cep, :street_address, :contact_name, :legal_name, :trade_name,
  /\Aec\z/, /\Aq\z/
]
