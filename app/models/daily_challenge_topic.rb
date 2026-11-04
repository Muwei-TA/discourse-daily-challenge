# frozen_string_literal: true

class DailyChallengeTopic < ActiveRecord::Base
  belongs_to :challenge, class_name: "DailyChallenge"
  belongs_to :topic
  validates :kind, inclusion: { in: %w[daily weekly final] }
  validates :publication_date, presence: true
end
