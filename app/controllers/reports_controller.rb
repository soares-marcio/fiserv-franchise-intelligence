class ReportsController < ApplicationController
  before_action :load_scope

  def index
    @reports = @scope.revenue_by_sub_channel
    @totals = @scope.totals
    respond_to do |format|
      format.html
      format.csv do
        send_data ReportsExporter.new(@reports, cutoff_day: @cutoff_day, totals: @totals).to_csv,
          filename: export_filename("csv"), type: "text/csv"
      end
      format.xlsx do
        send_data ReportsExporter.new(@reports, cutoff_day: @cutoff_day, totals: @totals).to_xlsx,
          filename: export_filename("xlsx"),
          type: Mime[:xlsx]
      end
    end
  end

  def stalled
    @reports = @scope.stalled_companies
  end

  def weekly
    @reports = @scope.weekly_revenue
  end

  private

  def load_scope
    @channels = Channel.order(:canal)
    @selected_channel = Channel.find_param!(params[:channel_id]) if params[:channel_id].present?
    @scope = ReportScope.new(channel_id: @selected_channel&.id)
    @cutoff_day = @scope.cutoff_day
  end

  def export_filename(extension)
    "auditoria-faturamento-dia-#{@cutoff_day || 'sem-corte'}.#{extension}"
  end
end
