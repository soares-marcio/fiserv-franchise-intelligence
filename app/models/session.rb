class Session < ApplicationRecord
  belongs_to :user

  # Dois limites, um de cada natureza: inatividade derruba quem esqueceu a tela aberta;
  # o absoluto derruba todo mundo uma vez por dia, mesmo em uso contínuo. Eram 2 h e 12 h até
  # 11/2026: a administradora reentrava várias vezes no mesmo dia, sempre com o segundo fator.
  INACTIVITY_LIMIT = 12.hours
  ABSOLUTE_LIMIT = 16.hours
  # last_active_at é escrito no máximo uma vez por minuto: sem isso, toda requisição vira
  # um UPDATE, e a tela de importação faz várias por segundo.
  TOUCH_INTERVAL = 1.minute

  scope :expired, -> {
    where(last_active_at: ...INACTIVITY_LIMIT.ago).or(where(created_at: ...ABSOLUTE_LIMIT.ago))
  }

  before_validation { self.last_active_at ||= Time.current }

  def expired?
    last_active_at < INACTIVITY_LIMIT.ago || created_at < ABSOLUTE_LIMIT.ago
  end

  def touch_activity
    return if last_active_at > TOUCH_INTERVAL.ago

    update_column(:last_active_at, Time.current)
  end
end
