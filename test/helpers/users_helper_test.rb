require "test_helper"

class UsersHelperTest < ActionView::TestCase
  test "iniciais do avatar vêm do primeiro e do último nome" do
    assert_equal "SM", user_initials(User.new(name: "Sheila Melo"))
    assert_equal "JS", user_initials(User.new(name: "juventino de souza"))
  end

  test "nome único dá uma inicial só" do
    assert_equal "T", user_initials(User.new(name: "Teste"))
  end
end
