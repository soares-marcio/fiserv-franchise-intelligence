class AuditEventsController < ApplicationController
  PER_PAGE = 50

  def index
    authorize :audit_event, :index?
    @events = policy_scope(AuditEvent).includes(:user, :channel).recent
      .limit(PER_PAGE).offset(offset)
    @page = page
    @has_more = policy_scope(AuditEvent).recent.limit(1).offset(offset + PER_PAGE).any?
  end

  private

  def page = [ params[:page].to_i, 1 ].max
  def offset = (page - 1) * PER_PAGE
end
