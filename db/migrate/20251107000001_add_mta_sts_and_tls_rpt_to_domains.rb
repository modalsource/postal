# frozen_string_literal: true

class AddMtaStsAndTlsRptToDomains < ActiveRecord::Migration[7.0]
  def change
    add_column :domains, :mta_sts_enabled, :boolean, default: false
    add_column :domains, :mta_sts_mode, :string, limit: 20, default: 'testing'
    add_column :domains, :mta_sts_max_age, :integer, default: 86400
    add_column :domains, :mta_sts_mx_patterns, :text
    add_column :domains, :mta_sts_status, :string, limit: 255
    add_column :domains, :mta_sts_error, :string, limit: 255
    add_column :domains, :tls_rpt_enabled, :boolean, default: false
    add_column :domains, :tls_rpt_email, :string, limit: 255
    add_column :domains, :tls_rpt_status, :string, limit: 255
    add_column :domains, :tls_rpt_error, :string, limit: 255
  end
end

