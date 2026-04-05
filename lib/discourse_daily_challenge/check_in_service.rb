# frozen_string_literal: true

module DiscourseDailyChallenge
  class CheckInService
    IMAGE_EXTENSIONS = %w[jpg jpeg png gif webp heic avif].freeze

    def self.process(post)
      return if post.topic_id.nil?

      challenge = DailyChallenge.find_by(topic_id: post.topic_id)
      return unless challenge&.active?

      user = post.user
      return unless user

      return unless has_hashtag?(post, challenge.hashtag) || has_image?(post)

      user_date = user_local_date(user)

      if challenge.check_in_interval == "weekly"
        week_start_date, week_end_date = current_week_window(challenge)
        return if DailyCheckIn.exists?(
          challenge_id: challenge.id,
          user_id: user.id,
          check_in_date: week_start_date..week_end_date,
        )
      else
        return if DailyCheckIn.exists?(
          challenge_id: challenge.id,
          user_id: user.id,
          check_in_date: user_date,
        )
      end

      DailyCheckIn.create!(
        challenge_id: challenge.id,
        user_id: user.id,
        check_in_date: user_date,
        post_id: post.id,
        admin_added: false,
      )

      clear_reminder_keys(challenge, user.id)

      total_check_ins = DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).count

      Jobs.enqueue(
        :discourse_daily_challenge_send_checkin_dm,
        user_id: user.id,
        challenge_id: challenge.id,
      )

      if total_check_ins == challenge.check_ins_needed
        Jobs.enqueue(
          :discourse_daily_challenge_send_completion_dm,
          user_id: user.id,
          challenge_id: challenge.id,
        )
      end
    rescue StandardError => e
      Rails.logger.error("DailyChallenge check-in error for post #{post.id}: #{e.message}")
    end

    def self.clear_reminder_keys(challenge, user_id)
      if challenge.check_in_interval == "weekly"
        tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
        today = Time.now.in_time_zone(tz).to_date
        wday = DiscourseDailyChallenge::ChallengeUtils.week_start_wday(challenge)
        week_start = DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(today, wday)
        Discourse.redis.del(
          "daily_challenge:reminder_weekly:#{challenge.id}:#{user_id}:#{week_start}",
        )
      else
        Discourse.redis.del(
          "daily_challenge:reminder_1:#{challenge.id}:#{user_id}",
          "daily_challenge:reminder_2:#{challenge.id}:#{user_id}",
        )
      end
    end

    def self.process_edit(post)
      return if post.topic_id.nil?

      challenge = DailyChallenge.find_by(topic_id: post.topic_id)
      return unless challenge&.active?

      user = post.user
      return unless user

      return unless has_hashtag?(post, challenge.hashtag) || has_image?(post)

      tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
      post_date = post.created_at.in_time_zone(tz).to_date

      if challenge.check_in_interval == "weekly"
        week_start_date, week_end_date = current_week_window(challenge)
        return unless post_date >= week_start_date && post_date <= week_end_date
        return if DailyCheckIn.exists?(
          challenge_id: challenge.id,
          user_id: user.id,
          check_in_date: week_start_date..week_end_date,
        )
      else
        return unless post.created_at >= 24.hours.ago
        return if DailyCheckIn.exists?(
          challenge_id: challenge.id,
          user_id: user.id,
          check_in_date: post_date,
        )
      end

      DailyCheckIn.create!(
        challenge_id: challenge.id,
        user_id: user.id,
        check_in_date: post_date,
        post_id: post.id,
        admin_added: false,
      )

      clear_reminder_keys(challenge, user.id)

      total_check_ins = DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).count

      Jobs.enqueue(
        :discourse_daily_challenge_send_checkin_dm,
        user_id: user.id,
        challenge_id: challenge.id,
      )

      if total_check_ins == challenge.check_ins_needed
        Jobs.enqueue(
          :discourse_daily_challenge_send_completion_dm,
          user_id: user.id,
          challenge_id: challenge.id,
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # duplicate check-in, silently skip
    rescue StandardError => e
      Rails.logger.error("DailyChallenge edit check-in error for post #{post.id}: #{e.message}")
    end

    def self.has_hashtag?(post, hashtag)
      return false if hashtag.blank?
      post.raw.to_s.match?(/(?:^|\s)##{Regexp.escape(hashtag)}(?:\b|$)/i)
    end

    def self.has_image?(post)
      post.uploads.any? { |u| IMAGE_EXTENSIONS.include?(u.extension.to_s.downcase) }
    end

    def self.user_local_date(user)
      tz_name = user.user_option&.timezone.presence || "UTC"
      tz = ActiveSupport::TimeZone[tz_name] || Time.zone
      Time.now.in_time_zone(tz).to_date
    end

    def self.current_week_window(challenge)
      tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
      today = Time.now.in_time_zone(tz).to_date
      wday = DiscourseDailyChallenge::ChallengeUtils.week_start_wday(challenge)
      week_start = DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(today, wday)
      [week_start, week_start + 6]
    end
  end
end
