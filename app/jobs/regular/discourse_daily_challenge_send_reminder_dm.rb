# frozen_string_literal: true

module Jobs
  class DiscourseDailyChallengeSendReminderDm < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.daily_challenge_enabled
      challenge = DailyChallenge.find_by(id: args[:challenge_id])
      return unless challenge&.active? && challenge.reminder_dms_enabled?
      bot = DiscourseDailyChallenge.bot_user
      return unless bot
      stage = args[:stage].to_s
      return unless %w[first second weekly].include?(stage)
      scope = challenge.check_ins.where(user_id: args[:user_id])
      last_date = scope.maximum(:check_in_date)
      return unless last_date

      if stage == 'weekly'
        wday = DiscourseDailyChallenge::ChallengeUtils.week_start_wday(challenge)
        week_start = DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(challenge.local_date, wday)
        return unless challenge.local_date == week_start + 6
        return if scope.exists?(check_in_date: week_start..(week_start + 6))
        key = "daily_challenge:reminder_weekly:#{challenge.id}:#{args[:user_id]}:#{week_start}"
      else
        missed_days = (challenge.local_date - last_date).to_i - 1
        return unless missed_days == (stage == 'first' ? 2 : 7)
        key = "daily_challenge:reminder_#{stage == 'first' ? 1 : 2}:#{challenge.id}:#{args[:user_id]}"
      end
      return if Discourse.redis.exists?(key)
      post = Jobs::DiscourseDailyChallengeSendReminders.new.send(
        :send_reminder_dm, bot, challenge, args[:user_id], stage.to_sym,
      )
      return unless post
      if stage == 'weekly'
        Discourse.redis.setex(key, 8.days.to_i, '1')
      else
        Discourse.redis.set(key, '1')
      end
    end
  end
end
