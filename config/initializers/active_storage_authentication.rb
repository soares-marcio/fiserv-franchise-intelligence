# Os controllers do Active Storage não herdam do ApplicationController — o próprio Rails
# avisa no código deles: "All Active Storage controllers are publicly accessible by
# default". Neste portal isso significa que a planilha original da BIN (CNPJ, telefone,
# endereço e faturamento de centenas de clientes) fica atrás de uma URL difícil de
# adivinhar, e nada mais.
#
# Todos herdam de ActiveStorage::BaseController, então um include cobre os quatro caminhos:
# blobs, representações, disco e upload direto.
Rails.application.config.to_prepare do
  ActiveStorage::BaseController.include(Authentication)

  # Quem serve arquivo também confere de quem ele é: sessão válida não basta para baixar o
  # anexo de uma anotação de outro Master.
  [ ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController ].each do |controller|
    controller.include(BlobAuthorization)
  end
end
