# frozen_string_literal: true

class AddDmarcFieldsToDomains < ActiveRecord::Migration[7.1]
  def change
    add_column :domains, :dmarc_status, :string
    add_column :domains, :dmarc_error, :string
  end
end
