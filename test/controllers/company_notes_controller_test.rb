require "test_helper"

class CompanyNotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    import_synthetic_workbook
    refresh_audit_views
    @company = Company.find_by!(cnpj: "11222333000181")
    @sub_channel = SubChannel.find_by!(name: "MIC ALFA")
  end

  test "salva a anotação e volta para o Clover Capital" do
    assert_difference -> { CompanyNote.count }, 1 do
      patch company_note_path(@company), params: { body: "<div>Dono viaja.</div>" }
    end

    assert_redirected_to stalled_reports_path
    assert_equal "Anotação salva.", flash[:notice]
    assert_equal "Dono viaja.", CompanyNote.find_by(cnpj: @company.cnpj).body.to_plain_text
  end

  # O recorte da listagem tem 13 parâmetros. Quem anotou na página 3, filtrada e ordenada,
  # precisa voltar para a página 3, filtrada e ordenada — é este teste que impede a lista de
  # chaves do controller de divergir do sub_channel_listing_params.
  test "voltando para a listagem do MIC, o recorte inteiro sobrevive" do
    recorte = {
      variation: "baixa", q: "ALFA", status: [ "Active" ], date_kind: [ "credenciamento" ],
      from_date: "2026-08-01", to_date: "2026-08-31", sort: "current_revenue",
      direction: "asc", period: "2026-08-01", from_day: "1", to_day: "20",
      per_page: "50", page: "3"
    }

    patch company_note_path(@company), params: {
      body: "<div>Ligar depois do dia 10.</div>",
      origin: "sub_channel", sub_channel_id: @sub_channel.uuid, **recorte
    }

    destino = response.location
    assert_includes destino, sub_channel_report_path(@sub_channel)
    recorte.except(:status, :date_kind).each do |chave, valor|
      assert_includes CGI.unescape(destino), "#{chave}=#{valor}", "#{chave} não voltou"
    end
    assert_includes CGI.unescape(destino), "status[]=Active"
    assert_includes CGI.unescape(destino), "date_kind[]=credenciamento"
  end

  # O Clover Capital ganhou filtro de MIC: salvar sem JavaScript precisa voltar para o mesmo
  # recorte, como já voltava com o Master escolhido.
  test "sem origem declarada, a volta ao Clover Capital mantém o recorte da tela" do
    patch company_note_path(@company), params: {
      body: "<div>Ligar.</div>",
      channel_id: @sub_channel.channel.uuid, sub_channel_id: @sub_channel.uuid
    }

    assert_redirected_to stalled_reports_path(channel_id: @sub_channel.channel.uuid,
      sub_channel_id: @sub_channel.uuid)
  end

  test "editor esvaziado remove a anotação" do
    Operations::SaveCompanyNote.call(cnpj: @company.cnpj, body: "<div>Alguma coisa.</div>")

    assert_difference -> { CompanyNote.count }, -1 do
      patch company_note_path(@company), params: { body: "<div><br></div>" }
    end

    assert_equal "Anotação removida.", flash[:notice]
  end

  test "corpo acima do limite volta com alerta e não altera a anotação" do
    Operations::SaveCompanyNote.call(cnpj: @company.cnpj, body: "<div>Original.</div>")

    patch company_note_path(@company),
      params: { body: "<div>#{'a' * (Operations::SaveCompanyNote::MAX_LENGTH + 1)}</div>" }

    assert_match(/limite/, flash[:alert])
    assert_equal "Original.", CompanyNote.find_by(cnpj: @company.cnpj).body.to_plain_text
  end

  # Nada que venha na requisição pode virar destino de redirect. A origem escolhe entre telas
  # conhecidas; qualquer outra coisa cai no fallback, sem erro e sem sair do portal.
  test "origem forjada ou incompleta cai no fallback, nunca em destino arbitrário" do
    [ { origin: "https://evil.example/x" }, { origin: "sub_channel" } ].each do |forjada|
      patch company_note_path(@company), params: { body: "<div>x</div>", **forjada }

      assert_redirected_to stalled_reports_path
    end
  end

  # Salvar deixou de recarregar a tela: o stream troca a célula do cliente e o aviso. O alvo é
  # o id que a própria partial escreve, pelo helper — o teste o monta pelo helper também, senão
  # passaria a conferir uma string que a tela não usa mais.
  test "salvar responde por turbo_stream, trocando a célula do cliente e o aviso" do
    patch company_note_path(@company), params: { body: "<div>Ligar.</div>" },
      as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(
      /target="#{ApplicationController.helpers.company_note_cell_id(@company.uuid)}"/,
      response.body
    )
    assert_match(/action="replace"/, response.body)
    # O aviso vem no mesmo lote, em vez de esperar a próxima navegação.
    assert_match(/target="flash"/, response.body)
    assert_match(/Anotação salva\./, response.body)
    # E a célula trocada já traz o ponto que avisa que há anotação.
    assert_match(/note-trigger__dot/, response.body)
  end

  # A ficha do cliente mostra o texto, e não só o botão: o mesmo stream troca os dois. Nas
  # telas de tabela esse segundo alvo não existe, e o Turbo ignora o que não encontra.
  test "salvar também troca o bloco de texto da ficha" do
    patch company_note_path(@company), params: { body: "<div>Dono viaja.</div>" },
      as: :turbo_stream

    assert_response :success
    assert_match(
      /target="#{ApplicationController.helpers.company_note_body_id(@company.uuid)}"/,
      response.body
    )
    assert_match(/Dono viaja\./, response.body)
  end

  # Cada tela conhecida volta para si mesma, e nenhuma delas sai de caminho vindo na
  # requisição: a origem escolhe entre destinos montados por route helper.
  test "a ficha e a listagem de estabelecimentos voltam para onde se anotou" do
    patch company_note_path(@company), params: { body: "<div>x</div>", origin: "establishment" }

    assert_redirected_to establishment_path(@company)

    patch company_note_path(@company), params: {
      body: "<div>y</div>", origin: "establishments", q: "PADARIA", page: "2", per_page: "50"
    }

    assert_redirected_to establishments_path(q: "PADARIA", per_page: "50", page: "2")
  end

  test "erro de validação também volta por turbo_stream, sem derrubar a tela" do
    patch company_note_path(@company), as: :turbo_stream,
      params: { body: "<div>#{'a' * (Operations::SaveCompanyNote::MAX_LENGTH + 1)}</div>" }

    assert_response :success
    assert_match(/target="flash"/, response.body)
    assert_match(/limite/, response.body)
  end

  test "uuid desconhecida não encontra cliente" do
    patch company_note_path(SecureRandom.uuid), params: { body: "<div>x</div>" }

    assert_response :not_found
    assert_empty CompanyNote.all
  end

  # O modal chega por Turbo Frame, sem layout, com o editor já preenchido.
  test "o formulário do modal chega sem layout, com o que já estava escrito" do
    Operations::SaveCompanyNote.call(cnpj: @company.cnpj, body: "<div>Escrito antes.</div>")

    get edit_company_note_path(@company), headers: { "Turbo-Frame" => "company_note" }

    assert_response :success
    assert_select "body", false, "o modal chega sem layout"
    assert_select "turbo-frame#company_note"
    assert_select "trix-editor"
    assert_match(/Escrito antes\./, response.body)
  end
end
