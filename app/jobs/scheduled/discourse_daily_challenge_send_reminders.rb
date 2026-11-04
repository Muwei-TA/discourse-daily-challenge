# frozen_string_literal: true

module Jobs
  class DiscourseDailyChallengeSendReminders < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.daily_challenge_enabled

      bot = DiscourseDailyChallenge.bot_user
      return unless bot

      DailyChallenge.active.select(&:active?).each do |challenge|
        next unless challenge.reminder_dms_enabled

        if challenge.check_in_interval == "weekly"
          send_weekly_reminders(bot, challenge)
        else
          send_daily_reminders(bot, challenge)
        end
      end
    end

    private

    def send_daily_reminders(bot, challenge)
      tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
      today = Time.now.in_time_zone(tz).to_date

      participant_ids =
        DailyCheckIn.where(challenge_id: challenge.id).distinct.pluck(:user_id)
      return if participant_ids.empty?

      participant_ids.each do |user_id|
        last_check_in =
          DailyCheckIn
            .where(challenge_id: challenge.id, user_id: user_id)
            .maximum(:check_in_date)
            &.to_date
        next unless last_check_in

        missed_days = (today - last_check_in).to_i - 1

        if missed_days == 2
          key = "daily_challenge:reminder_1:#{challenge.id}:#{user_id}"
          next if Discourse.redis.exists?(key)
          send_reminder_dm(bot, challenge, user_id, :first)
          Discourse.redis.set(key, "1")
        elsif missed_days == 7
          key = "daily_challenge:reminder_2:#{challenge.id}:#{user_id}"
          next if Discourse.redis.exists?(key)
          send_reminder_dm(bot, challenge, user_id, :second)
          Discourse.redis.set(key, "1")
        end
      end
    end

    def send_weekly_reminders(bot, challenge)
      tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
      today = Time.now.in_time_zone(tz).to_date
      wday = DiscourseDailyChallenge::ChallengeUtils.week_start_wday(challenge)
      week_start = DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(today, wday)

      # Only send on the last day of the challenge week
      return unless (today - week_start) == 6

      participant_ids =
        DailyCheckIn.where(challenge_id: challenge.id).distinct.pluck(:user_id)
      return if participant_ids.empty?

      checked_in_this_week =
        DailyCheckIn
          .where(
            challenge_id: challenge.id,
            user_id: participant_ids,
            check_in_date: week_start..(week_start + 6),
          )
          .distinct
          .pluck(:user_id)

      (participant_ids - checked_in_this_week).each do |user_id|
        key = "daily_challenge:reminder_weekly:#{challenge.id}:#{user_id}:#{week_start}"
        next if Discourse.redis.get(key)
        send_reminder_dm(bot, challenge, user_id, :weekly)
        Discourse.redis.setex(key, 8.days.to_i, "1")
      end
    end

    def send_reminder_dm(bot, challenge, user_id, stage)
      user = User.find_by(id: user_id)
      return unless user

      challenge_name = challenge.display_name
      topic_link = challenge.bot_link

      check_in_count =
        DailyCheckIn.where(challenge_id: challenge.id, user_id: user_id).count
      checkin_count_text =
        I18n.t("daily_challenge.bot.checkin_count", count: check_in_count)

      body_key =
        stage == :second ? "daily_challenge.bot.reminder_dm_body_2" : "daily_challenge.bot.reminder_dm_body"

      PostCreator.create!(
        bot,
        title: I18n.t("daily_challenge.bot.reminder_dm_title", challenge_name: challenge_name),
        raw: I18n.t(
          body_key,
          topic_link: topic_link,
          checkin_count: checkin_count_text,
          needed: challenge.check_ins_needed,
        ),
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true,
      )
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge reminder DM error for user #{user_id}, challenge #{challenge.id}: #{e.message}",
      )
    end
  end
end
