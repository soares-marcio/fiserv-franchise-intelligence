# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# Dados pessoais e cadastrais das planilhas BIN não podem vazar para o log.
# :ec usa regex ancorada porque o match parcial pegaria "endereco", "record", etc.
Rails.application.config.filter_parameters += [
  :cnpj, :cpf, :telefone, :cep, :endereco, :nome_contato, :razao_social, :nome_fantasia, /\Aec\z/
]
