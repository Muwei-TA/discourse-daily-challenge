# frozen_string_literal: true

module Jobs
  class DiscourseDailyChallengeSendCompletionDm < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.daily_challenge_enabled

      bot = DiscourseDailyChallenge.bot_user
      return unless bot

      user = User.find_by(id: args[:user_id])
      return unless user

      challenge = DailyChallenge.find_by(id: args[:challenge_id])
      return unless challenge

      challenge_name = challenge.display_name
      topic_link = challenge.bot_link

      check_ins = DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).count
      checkin_count_text = I18n.t("daily_challenge.bot.checkin_count", count: check_ins)

      raw =
        if challenge.award_badge && challenge.badge_name.present?
          I18n.t(
            "daily_challenge.bot.completion_dm_body_with_badge",
            topic_link: topic_link,
            check_ins: checkin_count_text,
            badge_name: challenge.badge_name,
          )
        else
          I18n.t(
            "daily_challenge.bot.completion_dm_body",
            topic_link: topic_link,
            check_ins: checkin_count_text,
          )
        end

      PostCreator.create!(
        bot,
        title: I18n.t("daily_challenge.bot.completion_dm_title"),
        raw: raw,
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true,
      )
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge completion DM error for user #{args[:user_id]}, challenge #{args[:challenge_id]}: #{e.message}",
      )
    end
  end
end
