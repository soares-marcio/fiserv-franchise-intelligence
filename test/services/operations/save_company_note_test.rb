require "test_helper"

# Anotação do analista sobre o cliente. É o primeiro dado do portal que não vem de planilha
# nenhuma — e, por isso, o primeiro que nenhuma reimportação reconstrói.
class Operations::SaveCompanyNoteTest < ActiveSupport::TestCase
  CNPJ = "11222333000181".freeze

  test "grava a anotação do cliente e carimba a hora" do
    nota = Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div>Dono viaja até dia 10.</div>")

    assert_equal CNPJ, nota.cnpj
    assert_equal "Dono viaja até dia 10.", nota.body.to_plain_text
    assert_in_delta Time.current, nota.updated_at, 5
  end

  # Decisão do usuário: uma nota por cliente, editável. Gravar por cima substitui.
  test "gravar de novo substitui, sem acumular" do
    Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div>Primeira leitura.</div>")
    nota = Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div>Voltou a vender.</div>")

    assert_equal 1, CompanyNote.where(cnpj: CNPJ).count
    assert_equal "Voltou a vender.", nota.body.to_plain_text
  end

  # Esvaziar o editor é o gesto de apagar: não há botão a mais na tela para isso.
  test "corpo vazio apaga a anotação" do
    Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div>Alguma coisa.</div>")

    assert_nil Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div><br></div>")
    assert_empty CompanyNote.where(cnpj: CNPJ)
  end

  test "recusa CNPJ fora do formato, sem gravar" do
    erro = assert_raises(ArgumentError) do
      Operations::SaveCompanyNote.call(cnpj: "123", body: "<div>x</div>")
    end

    assert_match(/CNPJ/, erro.message)
    assert_empty CompanyNote.all
  end

  # O limite existe para a nota caber na tela e no atributo que a leva ao modal. Precisa
  # levantar ArgumentError, e não RecordInvalid: é o ArgumentError que o controller converte
  # em alerta; RecordInvalid viraria 500.
  test "recusa corpo acima do limite, sem gravar" do
    erro = assert_raises(ArgumentError) do
      Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div>#{'a' * 20_001}</div>")
    end

    assert_match(/limite/, erro.message)
    assert_empty CompanyNote.all
  end

  # A razão de a tabela guardar o CNPJ em vez de uma FK para companies. Um db:rebuild
  # regenera id e uuid; o CNPJ volta igual porque vem da planilha. Aqui isso é simulado
  # apagando e recriando a empresa — com FK, a nota teria ido junto ou apontado para o
  # cliente errado.
  test "a anotação sobrevive à empresa ser recriada com outro id" do
    antiga = Company.create!(cnpj: CNPJ)
    Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div>Anotado antes.</div>")

    # O que um db:rebuild faz com a identidade: a linha vai embora e volta com outro id e
    # outro uuid, porque a sequência recomeça e o gen_random_uuid() sorteia de novo. Só o
    # CNPJ volta igual — ele vem da planilha.
    antiga.delete
    nova = Company.create!(cnpj: CNPJ)

    assert_not_equal antiga.id, nova.id
    assert_not_equal antiga.uuid, nova.uuid
    assert_equal "Anotado antes.", CompanyNote.find_by(cnpj: nova.cnpj).body.to_plain_text
  end

  # Rich text é HTML do usuário. O que entra pode ser qualquer coisa; o que sai da tela não
  # pode ser script. Quem garante isso é o sanitizador do Action Text, na renderização.
  test "não devolve script no HTML renderizado" do
    nota = Operations::SaveCompanyNote.call(
      cnpj: CNPJ, body: "<div>Ligar<script>alert(1)</script></div>"
    )

    assert_no_match(/<script/, nota.body.to_s)
    assert_match(/Ligar/, nota.body.to_s)
  end
end
