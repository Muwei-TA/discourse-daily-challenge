# frozen_string_literal: true

class AddCheckInScopeToDailyChallenges < ActiveRecord::Migration[7.0]
  def change
    # Existing challenges retain topic-only behavior after deployment.
    add_column :daily_challenges, :check_in_scope, :string, null: false, default: "topic"
    add_column :daily_challenges, :scope_tag, :string

    add_index :daily_challenges, [:check_in_scope, :scope_tag],
              name: "index_daily_challenges_on_scope_and_tag"
  end
end
