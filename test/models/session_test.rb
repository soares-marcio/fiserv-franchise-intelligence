require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(organization: default_organization, email_address: "sessao@exemplo.com", name: "Sessão", password: "senha-bem-longa-1")
  end

  test "expira por inatividade e por tempo absoluto" do
    active = @user.sessions.create!(last_active_at: Time.current)
    stop = @user.sessions.create!(last_active_at: 3.hours.ago)
    old_one = @user.sessions.create!(last_active_at: Time.current)
    old_one.update_column(:created_at, 13.hours.ago)

    assert_not active.expired?
    assert stop.expired?, "duas horas sem uso derruba a sessão"
    assert old_one.reload.expired?, "doze horas derrubam mesmo em uso contínuo"
    assert_equal [ stop.id, old_one.id ].sort, Session.expired.pluck(:id).sort
  end

  # Sem o intervalo, toda requisição viraria um UPDATE — e a tela de importação faz várias
  # por segundo enquanto o arquivo processa.
  test "a marca de atividade só é reescrita depois do intervalo" do
    session_row = @user.sessions.create!(last_active_at: 10.seconds.ago)
    before = session_row.last_active_at

    session_row.touch_activity

    assert_equal before.to_i, session_row.reload.last_active_at.to_i

    session_row.update_column(:last_active_at, 2.minutes.ago)
    session_row.touch_activity

    assert_operator session_row.reload.last_active_at, :>, 1.minute.ago
  end
end
