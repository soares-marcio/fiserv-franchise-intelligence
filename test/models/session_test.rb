require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "sessao@exemplo.com", name: "Sessão", password: "senha-bem-longa-1")
  end

  test "expira por inatividade e por tempo absoluto" do
    ativa = @user.sessions.create!(last_active_at: Time.current)
    parada = @user.sessions.create!(last_active_at: 3.hours.ago)
    velha = @user.sessions.create!(last_active_at: Time.current)
    velha.update_column(:created_at, 13.hours.ago)

    assert_not ativa.expired?
    assert parada.expired?, "duas horas sem uso derruba a sessão"
    assert velha.reload.expired?, "doze horas derrubam mesmo em uso contínuo"
    assert_equal [ parada.id, velha.id ].sort, Session.expired.pluck(:id).sort
  end

  # Sem o intervalo, toda requisição viraria um UPDATE — e a tela de importação faz várias
  # por segundo enquanto o arquivo processa.
  test "a marca de atividade só é reescrita depois do intervalo" do
    sessao = @user.sessions.create!(last_active_at: 10.seconds.ago)
    antes = sessao.last_active_at

    sessao.touch_activity

    assert_equal antes.to_i, sessao.reload.last_active_at.to_i

    sessao.update_column(:last_active_at, 2.minutes.ago)
    sessao.touch_activity

    assert_operator sessao.reload.last_active_at, :>, 1.minute.ago
  end
end
