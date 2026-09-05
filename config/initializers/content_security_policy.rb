# Política de segurança de conteúdo: tudo vem da própria origem. A fonte Montserrat e os
# ícones Phosphor estão vendorizados, o JavaScript é importmap servido pelo app e não há
# script nem estilo inline escrito à mão — então nada precisa de exceção para fora.
#
# style-src aceita 'unsafe-inline' porque o Turbo escreve estilo inline ao animar a troca de
# página; o nonce não chega até lá. Script, esse sim, exige nonce.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # O nonce muda a cada requisição e é o que autoriza o importmap; sem sessão iniciada
  # (o portal não tem login), o id da sessão é vazio, então vale um valor sorteado.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
