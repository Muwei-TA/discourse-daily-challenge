# frozen_string_literal: true

class AddWelcomeMessageToDailyChallenges < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:daily_challenges)
    add_column :daily_challenges, :welcome_message, :text unless column_exists?(
      :daily_challenges,
      :welcome_message,
    )
  end

  def down
    return unless table_exists?(:daily_challenges)
    remove_column :daily_challenges, :welcome_message if column_exists?(:daily_challenges, :welcome_message)
  end
end
