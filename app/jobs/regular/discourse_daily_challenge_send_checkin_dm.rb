# frozen_string_literal: true

module Jobs
  class DiscourseDailyChallengeSendCheckinDm < ::Jobs::Base
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
      topic_link =
        if topic
          "[**#{challenge_name}**](#{Discourse.base_url}/t/#{topic.slug}/#{topic.id})"
        else
          "**#{challenge_name}**"
        end

      check_ins = DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).count
      needed = challenge.check_ins_needed

      bot_username = SiteSetting.daily_challenge_bot_username.presence || bot.username

      raw =
        if check_ins == 1
          onboarding = I18n.t(
            "daily_challenge.bot.onboarding_dm_body",
            challenge_name: challenge_name,
            hashtag: challenge.hashtag,
            check_ins_needed: needed,
            end_date: challenge.end_date.strftime("%B %-d, %Y"),
            bot_username: bot_username,
          )
          onboarding = "#{onboarding}\n\n#{challenge.welcome_message}" if challenge.welcome_message.present?
          I18n.t(
            "daily_challenge.bot.checkin_dm_body_first",
            topic_link: topic_link,
            needed: needed,
          ) + "\n\n---\n\n" + onboarding
        else
          streak = DiscourseDailyChallenge::ChallengeUtils.user_streak(challenge, user.id)
          streak_text =
            if challenge.check_in_interval == "weekly"
              I18n.t("daily_challenge.bot.streak_week", count: streak)
            else
              I18n.t("daily_challenge.bot.streak_day", count: streak)
            end
          I18n.t(
            "daily_challenge.bot.checkin_dm_body",
            topic_link: topic_link,
            streak_text: streak_text,
            check_ins: check_ins,
            needed: needed,
          )
        end

      title =
        if check_ins == 1
          I18n.t("daily_challenge.bot.onboarding_dm_title", challenge_name: challenge_name)
        else
          I18n.t("daily_challenge.bot.checkin_dm_title")
        end

      PostCreator.create!(
        bot,
        title: title,
        raw: raw,
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true,
      )
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge checkin DM error for user #{args[:user_id]}, challenge #{args[:challenge_id]}: #{e.message}",
      )
    end
  end
end
