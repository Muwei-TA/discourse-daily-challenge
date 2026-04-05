# frozen_string_literal: true

module Jobs
  class DiscourseDailyChallengeSendOnboardingDm < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.daily_challenge_enabled

      bot = DiscourseDailyChallenge.bot_user
      return unless bot

      user = User.find_by(id: args[:user_id])
      return unless user

      challenge = DailyChallenge.find_by(id: args[:challenge_id])
      return unless challenge

      topic = challenge.topic
      challenge_name = topic&.title || "##{challenge.hashtag}"

      bot_username = SiteSetting.daily_challenge_bot_username.presence || bot.username

      end_date_formatted = challenge.end_date.strftime("%B %-d, %Y")

      raw = I18n.t(
        "daily_challenge.bot.onboarding_dm_body",
        challenge_name: challenge_name,
        hashtag: challenge.hashtag,
        check_ins_needed: challenge.check_ins_needed,
        end_date: end_date_formatted,
        bot_username: bot_username,
      )

      if challenge.welcome_message.present?
        raw = "#{raw}\n\n#{challenge.welcome_message}"
      end

      PostCreator.create!(
        bot,
        title: I18n.t("daily_challenge.bot.onboarding_dm_title", challenge_name: challenge_name),
        raw: raw,
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true,
      )
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge onboarding DM error for user #{args[:user_id]}, challenge #{args[:challenge_id]}: #{e.message}",
      )
    end
  end
end
