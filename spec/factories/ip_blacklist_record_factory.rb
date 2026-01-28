# frozen_string_literal: true

# == Schema Information
#
# Table name: ip_blacklist_records
#
#  id                 :integer          not null, primary key
#  blacklist_source   :string(255)      not null
#  check_count        :integer          default(0)
#  destination_domain :string(255)      not null
#  details            :text(65535)
#  detected_at        :datetime         not null
#  last_checked_at    :datetime
#  resolved_at        :datetime
#  status             :string(255)      default("active"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  ip_address_id      :integer          not null
#
# Indexes
#
#  index_blacklist_on_ip_domain_source                       (ip_address_id,destination_domain,blacklist_source) UNIQUE
#  index_ip_blacklist_records_on_destination_domain          (destination_domain)
#  index_ip_blacklist_records_on_ip_address_id               (ip_address_id)
#  index_ip_blacklist_records_on_status_and_last_checked_at  (status,last_checked_at)
#
# Foreign Keys
#
#  fk_rails_...  (ip_address_id => ip_addresses.id)
#
FactoryBot.define do
  factory :ip_blacklist_record do
    ip_address
    destination_domain { "gmail.com" }
    blacklist_source { "spamhaus_zen" }
    status { "active" }
    detected_at { Time.current }
    check_count { 1 }

    trait :resolved do
      status { "resolved" }
      resolved_at { Time.current }
    end

    trait :ignored do
      status { "ignored" }
    end

    trait :with_details do
      details { { reason: "Listed for spam", code: 127 }.to_json }
    end
  end
end
