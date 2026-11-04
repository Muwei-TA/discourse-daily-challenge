# frozen_string_literal: true

module DiscourseDailyChallenge
  class CheckInService
    IMAGE_EXTENSIONS = %w[jpg jpeg png gif webp heic avif].freeze

    def self.process(post)
      return if post.topic_id.nil? || !eligible_author?(post)

      matching_challenges(post).each do |challenge|
        next unless valid_check_in?(post, challenge)

        record_check_in(challenge, post, check_in_date: user_local_date(post.user))
      end
    rescue StandardError => e
      Rails.logger.error("DailyChallenge check-in error for post #{post.id}: #{e.message}")
    end

    def self.process_edit(post)
      return if post.topic_id.nil? || !eligible_author?(post)

      matching_challenges(post).each do |challenge|
        next unless valid_check_in?(post, challenge)

        tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
        post_date = post.created_at.in_time_zone(tz).to_date

        if challenge.check_in_interval == "weekly"
          week_start_date, week_end_date = current_week_window(challenge)
          next unless post_date >= week_start_date && post_date <= week_end_date
        else
          next unless post.created_at >= 24.hours.ago
        end

        record_check_in(challenge, post, check_in_date: post_date)
      end
    rescue StandardError => e
      Rails.logger.error("DailyChallenge edit check-in error for post #{post.id}: #{e.message}")
    end

    # The challenge topic remains the destination for leaderboards and announcements.
    # Additional scopes only affect where check-in posts may originate.
    def self.matching_challenges(post)
      scoped = DailyChallenge.active.where(topic_id: post.topic_id, check_in_scope: "topic").to_a

      topic = post.topic
      return scoped unless public_topic?(topic)

      tag_names = topic.tags.map { |tag| tag.name.downcase }
      if tag_names.present?
        scoped.concat(
          DailyChallenge.active.where(check_in_scope: "topic_tag", scope_tag: tag_names).to_a,
        )
      end

      # Only explicit challenge hashtags count in this mode; ordinary image posts
      # elsewhere on the site must never silently trigger check-ins.
      scoped.concat(DailyChallenge.active.where(check_in_scope: "site_hashtag").to_a)
      scoped.uniq(&:id)
    end

    def self.public_topic?(topic)
      topic.present? && topic.archetype == Archetype.default && topic.visible? &&
        topic.category.present? && !topic.category.read_restricted?
    end

    def self.eligible_author?(post)
      user = post.user
      user.present? && !user.anonymous? && !user.bot? && post.post_type == Post.types[:regular]
    end

    def self.valid_check_in?(post, challenge)
      return false unless challenge.active?
      return has_hashtag?(post, challenge.hashtag) if challenge.check_in_scope == "site_hashtag"

      has_hashtag?(post, challenge.hashtag) || has_image?(post)
    end

    def self.record_check_in(challenge, post, check_in_date:)
      user = post.user

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
          check_in_date: check_in_date,
        )
      end

      DailyCheckIn.create!(
        challenge_id: challenge.id,
        user_id: user.id,
        check_in_date: check_in_date,
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
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Concurrent posts or edits can race on the unique challenge/user/date index.
      raise unless DailyCheckIn.exists?(
        challenge_id: challenge.id,
        user_id: user.id,
        check_in_date: check_in_date,
      )
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

    def self.has_hashtag?(post, hashtag)
      return false if hashtag.blank?
      # Permit Markdown/backticks around the hashtag, but reject partial words.
      post.raw.to_s.match?(/(?<![[:alnum:]])##{Regexp.escape(hashtag)}(?![[:alnum:]])/i)
    end

    def self.has_image?(post)
      post.uploads.any? { |u| IMAGE_EXTENSIONS.include?(u.extension.to_s.downcase) }
    end

    def self.user_local_date(user)
      tz_name = user.user_option&.timezone.presence || "UTC"
      tz = ActiveSupport::TimeZone[tz_name] || Time.zone
      Time.now.in_time_zone(tz).to_date
    end

    def self.challenge_local_date(challenge)
      tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
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
