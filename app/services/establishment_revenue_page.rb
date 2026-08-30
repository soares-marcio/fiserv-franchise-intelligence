class EstablishmentRevenuePage
  include Enumerable

  attr_reader :rows, :total_count, :totals, :page, :per_page

  def initialize(rows:, total_count:, totals:, page:, per_page:)
    @rows = rows
    @total_count = total_count.to_i
    @totals = totals
    @page = page
    @per_page = per_page
  end

  def each(&block)
    rows.each(&block)
  end

  def total_pages
    return 1 if total_count < 1 || per_page.to_i < 1

    (total_count.to_f / per_page).ceil
  end
end
