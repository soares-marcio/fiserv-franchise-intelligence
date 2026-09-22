# QR do autenticador, desenhado como SVG inline. Inline de propósito: é marcação, fora do
# alcance da CSP, e não cria rota nova servindo imagem derivada de segredo.
class QrCode
  def self.svg(uri)
    RQRCode::QRCode.new(uri, level: :m).as_svg(
      module_size: 4, standalone: true, use_path: true, viewbox: true
    ).html_safe
  end
end
