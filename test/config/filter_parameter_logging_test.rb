require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  # A busca aceita CNPJ por design; o parâmetro não pode aparecer em claro no log.
  test "o termo de busca é filtrado do log" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter("q" => "12.345.678/0001-90", "page" => "2")

    assert_equal "[FILTERED]", filtered["q"]
    assert_equal "2", filtered["page"]
  end
end
