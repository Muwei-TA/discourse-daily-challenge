# frozen_string_literal: true

class AddDailyChallengeTopics < ActiveRecord::Migration[7.2]
  def change
    change_column_null :daily_challenges, :topic_id, true
    add_column :daily_challenges, :name, :string
    add_column :daily_challenges, :tag_id, :integer
    add_column :daily_challenges, :daily_topics_enabled, :boolean, null: false, default: false
    add_column :daily_challenges, :publication_error, :text
    add_column :daily_challenges, :publication_error_at, :datetime
    add_index :daily_challenges, :tag_id

    create_table :daily_challenge_topics do |t|
      t.integer :challenge_id, null: false
      t.integer :topic_id, null: false
      t.string :kind, null: false
      t.date :publication_date, null: false
      t.timestamps
    end
    add_index :daily_challenge_topics, :topic_id, unique: true
    add_index :daily_challenge_topics, [:challenge_id, :kind, :publication_date],
              unique: true, name: "idx_daily_challenge_publication"
  end
end
