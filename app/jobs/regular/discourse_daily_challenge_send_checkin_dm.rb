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

      check_ins_scope = challenge.check_ins.where(user_id: user.id)
      check_in = if args[:check_in_id]
        check_ins_scope.find_by(id: args[:check_in_id])
      else
        check_ins_scope.order(check_in_date: :desc, id: :desc).first
      end
      return unless check_in

      challenge_name = challenge.display_name
      topic_link = challenge.bot_link

      check_ins = DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).count
      needed = challenge.check_ins_needed

      bot_username = SiteSetting.daily_challenge_bot_username.presence || bot.username

      raw =
        if check_ins == 1
          onboarding = I18n.t(
            "daily_challenge.bot.onboarding_dm_body",
            challenge_name: challenge_name,
            hashtag: challenge.display_tag,
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

      DiscourseDailyChallenge::AiNotification.deliver(
        event_key: "checkin:#{check_in.id}", kind: :checkin,
        challenge: challenge, user: user, check_in: check_in,
        fallback_sender: bot, title: title, fallback_raw: raw,
      )
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge checkin DM error for user #{args[:user_id]}, challenge #{args[:challenge_id]}: #{e.message}",
      )
      raise
    end
  end
end
