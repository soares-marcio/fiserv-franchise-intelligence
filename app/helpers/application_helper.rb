module ApplicationHelper
  def aligned_variation(previous, current)
    previous = previous.to_d
    current = current.to_d
    return "—" if previous.zero?

    number_to_percentage((current / previous - 1) * 100, precision: 1)
  end

  def variation_badge_class(previous, current)
    previous = previous.to_d
    current = current.to_d
    return "badge badge-ghost" if previous.zero?

    current >= previous ? "badge badge-success" : "badge badge-error"
  end

  def brl(amount)
    number_to_currency(amount.to_d, unit: "R$", separator: ",", delimiter: ".")
  end
end
