# frozen_string_literal: true

# IP Blacklist Records Management Controller
# Allows admins to view, resolve, ignore, and recheck blacklist records
class IPBlacklistRecordsController < ApplicationController

  before_action :admin_required
  before_action :load_record, only: [:show, :resolve, :ignore, :recheck]

  # GET /ip_blacklist_records
  # List all blacklist records with filtering
  def index
    @records = IPBlacklistRecord.includes(:ip_address).order(created_at: :desc)

    # Apply filters
    @records = @records.where(status: params[:status]) if params[:status].present?
    @records = @records.where(ip_address_id: params[:ip_address_id]) if params[:ip_address_id].present?
    @records = @records.where(blacklist_source: params[:blacklist]) if params[:blacklist].present?
    @records = @records.where(destination_domain: params[:domain]) if params[:domain].present?

    # Pagination
    @page = (params[:page] || 1).to_i
    @per_page = (params[:per_page] || 50).to_i.clamp(1, 100)
    @total_count = @records.count
    @total_pages = (@total_count.to_f / @per_page).ceil
    @records = @records.limit(@per_page).offset((@page - 1) * @per_page)

    # Load data for filters
    @ip_addresses = IPAddress.all

    respond_to do |format|
      format.html
      format.json { render json: records_json }
    end
  end

  # GET /ip_blacklist_records/:id
  # Show detailed information about a blacklist record
  def show
    @related_records = IPBlacklistRecord
                       .where(ip_address: @record.ip_address)
                       .where.not(id: @record.id)
                       .order(created_at: :desc)
                       .limit(10)

    @health_actions = @record.ip_address.ip_health_actions
                             .where("created_at >= ?", @record.created_at)
                             .order(created_at: :desc)
                             .limit(20)

    respond_to do |format|
      format.html
      format.json { render json: record_detail_json }
    end
  end

  # POST /ip_blacklist_records/:id/resolve
  # Mark a blacklist as resolved and trigger recovery
  def resolve
    if @record.resolved?
      return render json: { error: "Already resolved" }, status: :unprocessable_content
    end

    @record.mark_resolved!

    # Trigger warmup if configured and domain-specific
    if @record.destination_domain.present? && Postal::Config.ip_reputation&.auto_warmup_on_delist != false
      IPBlacklist::WarmupManager.start_warmup(
        @record.ip_address,
        @record.destination_domain,
        reason: "Auto-warmup after delisting from #{@record.blacklist_source}"
      )
    end

    message = "Blacklist record marked as resolved"

    respond_to do |format|
      format.html { redirect_back fallback_location: ip_blacklist_records_path, notice: message }
      format.json { render json: { success: true, message: message, record: @record } }
    end
  end

  # POST /ip_blacklist_records/:id/ignore
  # Mark a blacklist as ignored (false positive)
  def ignore
    reason = params[:reason] || "Ignored by #{current_user.name}"

    @record.update!(
      status: "ignored",
      resolved_at: Time.current
    )

    # Log action
    IPHealthAction.create!(
      ip_address: @record.ip_address,
      action_type: IPHealthAction::MONITOR,
      destination_domain: @record.destination_domain,
      reason: "Blacklist ignored: #{reason}",
      triggered_by_blacklist: @record,
      user: current_user
    )

    message = "Blacklist record marked as ignored"

    respond_to do |format|
      format.html { redirect_back fallback_location: ip_blacklist_records_path, notice: message }
      format.json { render json: { success: true, message: message } }
    end
  end

  # POST /ip_blacklist_records/:id/recheck
  # Manually trigger a recheck of this blacklist
  def recheck
    checker = IPBlacklist::Checker.new(@record.ip_address)
    result = checker.check_single_dnsbl(@record.blacklist_source, @record.destination_domain)

    if result[:listed]
      message = "Still blacklisted on #{@record.blacklist_source}"
      @record.update!(last_checked_at: Time.current)
    else
      @record.mark_resolved!(resolved_by: current_user, resolution_notes: "Confirmed delisted via manual recheck")
      message = "Confirmed delisted from #{@record.blacklist_source}"
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: ip_blacklist_record_path(@record), notice: message }
      format.json { render json: { success: true, message: message, listed: result[:listed] } }
    end
  rescue StandardError => e
    error_message = "Recheck failed: #{e.message}"
    respond_to do |format|
      format.html { redirect_back fallback_location: ip_blacklist_record_path(@record), alert: error_message }
      format.json { render json: { error: error_message }, status: :unprocessable_content }
    end
  end

  private

  def load_record
    @record = IPBlacklistRecord.includes(:ip_address).find(params[:id])
  end

  def records_json
    {
      records: @records.map do |record|
        {
          id: record.id,
          ip: record.ip_address.ipv4,
          blacklist: record.blacklist_source,
          domain: record.destination_domain,
          detection_method: record.detection_method,
          status: record.status,
          created_at: record.created_at,
          resolved_at: record.resolved_at,
          last_checked_at: record.last_checked_at
        }
      end,
      pagination: {
        page: @page,
        per_page: @per_page,
        total: @total,
        total_pages: (@total.to_f / @per_page).ceil
      }
    }
  end

  def record_detail_json
    {
      record: {
        id: @record.id,
        ip_address: {
          id: @record.ip_address.id,
          ipv4: @record.ip_address.ipv4,
          hostname: @record.ip_address.hostname
        },
        blacklist_source: @record.blacklist_source,
        destination_domain: @record.destination_domain,
        detection_method: @record.detection_method,
        status: @record.status,
        details: @record.details,
        smtp_response_code: @record.smtp_response_code,
        smtp_response_message: @record.smtp_response_message,
        created_at: @record.created_at,
        resolved_at: @record.resolved_at,
        last_checked_at: @record.last_checked_at,
        resolution_notes: @record.resolution_notes
      },
      related_records: @related_records.map do |r|
        {
          id: r.id,
          blacklist: r.blacklist_source,
          domain: r.destination_domain,
          status: r.status,
          created_at: r.created_at
        }
      end,
      health_actions: @health_actions.map do |action|
        {
          id: action.id,
          action_type: action.action_type,
          reason: action.reason,
          created_at: action.created_at,
          user: action.user&.name
        }
      end
    }
  end

end
