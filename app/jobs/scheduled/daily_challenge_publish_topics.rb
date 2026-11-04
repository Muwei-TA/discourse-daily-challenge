# frozen_string_literal: true

module Jobs
  class DailyChallengePublishTopics < ::Jobs::Scheduled
    every 1.minute

    def execute(_args)
      return unless SiteSetting.daily_challenge_enabled
      DailyChallenge.active.where(daily_topics_enabled: true).find_each do |challenge|
        DiscourseDailyChallenge::TopicPublisher.publish_today(challenge)
      rescue StandardError
        # Persisted on the challenge; a bad configuration must not block others.
      end
    end
  end
end
