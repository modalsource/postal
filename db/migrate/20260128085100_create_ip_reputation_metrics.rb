# frozen_string_literal: true

class CreateIPReputationMetrics < ActiveRecord::Migration[6.1]

  def change
    create_table :ip_reputation_metrics, id: :integer do |t|
      t.integer :ip_address_id, null: false
      t.string :destination_domain
      t.string :sender_domain
      t.string :period, null: false, default: "daily"
      t.date :period_date, null: false

      # Message counters
      t.integer :sent_count, default: 0
      t.integer :delivered_count, default: 0
      t.integer :bounced_count, default: 0
      t.integer :soft_fail_count, default: 0
      t.integer :hard_fail_count, default: 0
      t.integer :spam_complaint_count, default: 0

      # Calculated rates (percentage * 10000 for precision)
      t.integer :bounce_rate, default: 0
      t.integer :delivery_rate, default: 0
      t.integer :spam_rate, default: 0

      # Reputation score (0-100)
      t.integer :reputation_score, default: 100

      t.timestamps
    end

    add_index :ip_reputation_metrics, :ip_address_id
    add_index :ip_reputation_metrics, [:ip_address_id, :destination_domain, :period, :period_date],
              name: "index_reputation_on_ip_dest_period", unique: true
    add_index :ip_reputation_metrics, :reputation_score
    add_index :ip_reputation_metrics, :period_date
    add_foreign_key :ip_reputation_metrics, :ip_addresses
  end

end
