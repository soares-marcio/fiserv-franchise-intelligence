require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  # A busca aceita CNPJ por design; o parâmetro não pode aparecer em claro no log.
  test "o termo de busca é filtrado do log" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter("q" => "12.345.678/0001-90", "page" => "2")

    assert_equal "[FILTERED]", filtered["q"]
    assert_equal "2", filtered["page"]
  end

  # O mesmo campo recebe o código do autenticador e o de recuperação, e o log no berry fica
  # guardado 30 dias: um código de recuperação digitado com erro sairia quase inteiro no arquivo.
  test "o código do segundo fator é filtrado do log" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter("code" => "abcd-efgh-ijkl", "cnae_code" => "4711302")

    assert_equal "[FILTERED]", filtered["code"]
    assert_equal "4711302", filtered["cnae_code"]
  end
end
