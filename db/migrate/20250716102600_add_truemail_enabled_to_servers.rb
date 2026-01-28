# frozen_string_literal: true

class AddTruemailEnabledToServers < ActiveRecord::Migration[7.0]
  def change
    add_column :servers, :truemail_enabled, :boolean, default: false
  end
end
