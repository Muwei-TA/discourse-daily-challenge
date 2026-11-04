# frozen_string_literal: true

module DiscourseDailyChallenge
  class MentionHandler
    def self.handle(post)
      return unless SiteSetting.daily_challenge_enabled

      bot_username = SiteSetting.daily_challenge_bot_username.presence
      return unless bot_username

      bot = User.find_by(username: bot_username)
      return unless bot

      # Don't respond to the bot's own posts
      return if post.user_id == bot.id

      return if post.post_type != Post.types[:regular]

      # Check if bot is mentioned
      return unless post.raw.to_s.include?("@#{bot_username}")

      # Find active challenge for this topic
      publication = DailyChallengeTopic.find_by(topic_id: post.topic_id)
      challenge = publication&.challenge || DailyChallenge.find_by(topic_id: post.topic_id, daily_topics_enabled: false)
      return unless challenge&.active?

      user = post.user
      return unless user

      # Parse command: first word after the @mention
      after_mention = post.raw.to_s.sub(/.*@#{Regexp.escape(bot_username)}/im, "").strip
      command = after_mention.split.first.to_s.downcase

      # Rate limit: max 10 commands per user per hour
      rate_key = "daily_challenge_bot_rate_limit:#{post.user_id}"
      count = Discourse.redis.incr(rate_key)
      Discourse.redis.expire(rate_key, 1.hour.to_i) if count == 1
      if count > 10
        PostCreator.create!(
          bot,
          title: I18n.t("daily_challenge.bot.rate_limit_dm_title"),
          raw: I18n.t("daily_challenge.bot.rate_limit_dm_body"),
          archetype: Archetype.private_message,
          target_usernames: [user.username],
          skip_validations: true,
        )
        return
      end

      # Plain text for the PM subject line (markdown doesn't render there)
      challenge_name = challenge.display_name
      response = build_response(command, challenge, user, bot_username)

      PostCreator.create!(
        bot,
        title: I18n.t(
          "daily_challenge.bot.mention_dm_title",
          command: command.presence || "help",
          challenge_name: challenge_name,
        ),
        raw: response,
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true,
      )
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge MentionHandler error for post #{post.id}: #{e.message}",
      )
    end

    def self.build_response(command, challenge, user, bot_username)
      case command
      when "status"
        status_response(user)
      when "leaderboard"
        leaderboard_response(challenge)
      when "streak"
        streak_response(challenge, user)
      when "checkins"
        checkins_response(challenge, user)
      when "progress"
        progress_response(challenge, user)
      when "help"
        help_response(bot_username)
      else
        "#{I18n.t("daily_challenge.bot.commands.unknown_command")}\n\n#{help_response(bot_username)}"
      end
    end

    def self.status_response(user)
      active_challenges = DailyChallenge.active.select(&:active?)
      participated =
        active_challenges.select do |c|
          DailyCheckIn.where(challenge_id: c.id, user_id: user.id).exists?
        end

      return I18n.t("daily_challenge.bot.commands.status_none") if participated.empty?

      rows =
        participated.map do |c|
          check_ins = DailyCheckIn.where(challenge_id: c.id, user_id: user.id).count
          streak = ChallengeUtils.user_streak(c, user.id)
          streak_text =
            if c.check_in_interval == "weekly"
              I18n.t("daily_challenge.bot.streak_week", count: streak)
            else
              I18n.t("daily_challenge.bot.streak_day", count: streak)
            end
          pct =
            c.check_ins_needed > 0 ? ((check_ins.to_f / c.check_ins_needed) * 100).round : 0
          I18n.t(
            "daily_challenge.bot.commands.status_row",
            challenge: challenge_link(c),
            check_ins: check_ins,
            streak: streak_text,
            pct: pct,
          )
        end

      "#{I18n.t("daily_challenge.bot.commands.status_header")}\n\n#{rows.join("\n")}"
    end

    def self.leaderboard_response(challenge)
      header =
        I18n.t(
          "daily_challenge.bot.commands.leaderboard_header",
          challenge: challenge_link(challenge),
        )

      top =
        DailyCheckIn
          .where(challenge_id: challenge.id)
          .group(:user_id)
          .order("count_all DESC")
          .count
          .first(10)

      if top.empty?
        return "#{header}\n\n#{I18n.t("daily_challenge.bot.commands.leaderboard_none")}"
      end

      users_by_id = User.where(id: top.map(&:first)).index_by(&:id)
      rows =
        top.each_with_index.filter_map do |(user_id, count), idx|
          u = users_by_id[user_id]
          next unless u
          I18n.t(
            "daily_challenge.bot.commands.leaderboard_row",
            rank: idx + 1,
            username: u.username,
            count: count,
          )
        end

      "#{header}\n\n#{rows.join("\n")}"
    end

    def self.streak_response(challenge, user)
      unless DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).exists?
        return I18n.t(
          "daily_challenge.bot.commands.streak_none",
          challenge: challenge_link(challenge),
        )
      end

      streak = ChallengeUtils.user_streak(challenge, user.id)
      streak_text =
        if challenge.check_in_interval == "weekly"
          I18n.t("daily_challenge.bot.streak_week", count: streak)
        else
          I18n.t("daily_challenge.bot.streak_day", count: streak)
        end

      I18n.t(
        "daily_challenge.bot.commands.streak_message",
        challenge: challenge_link(challenge),
        streak_text: streak_text,
      )
    end

    def self.checkins_response(challenge, user)
      dates =
        DailyCheckIn
          .where(challenge_id: challenge.id, user_id: user.id)
          .order(check_in_date: :asc)
          .pluck(:check_in_date)

      header =
        I18n.t(
          "daily_challenge.bot.commands.checkins_header",
          challenge: challenge_link(challenge),
          count: dates.size,
        )

      if dates.empty?
        return "#{header}\n\n#{I18n.t("daily_challenge.bot.commands.checkins_none")}"
      end

      rows = dates.map { |d| I18n.t("daily_challenge.bot.commands.checkins_row", date: d.strftime("%B %-d, %Y")) }
      "#{header}\n\n#{rows.join("\n")}"
    end

    def self.progress_response(challenge, user)
      done = DailyCheckIn.where(challenge_id: challenge.id, user_id: user.id).count
      needed = challenge.check_ins_needed

      today = challenge.local_date
      days_left = [(challenge.end_date - today).to_i, 0].max

      time_remaining =
        if challenge.check_in_interval == "weekly"
          I18n.t(
            "daily_challenge.bot.commands.progress_time_remaining_week",
            count: (days_left / 7.0).ceil,
          )
        else
          I18n.t("daily_challenge.bot.commands.progress_time_remaining_day", count: days_left)
        end

      status =
        if done >= needed
          I18n.t("daily_challenge.bot.commands.progress_complete")
        else
          total_days = (challenge.end_date - challenge.start_date).to_i + 1
          elapsed = challenge.elapsed_days
          expected = total_days > 0 ? ((elapsed.to_f / total_days) * needed).ceil : 0
          if done >= expected
            I18n.t("daily_challenge.bot.commands.progress_on_track")
          else
            I18n.t("daily_challenge.bot.commands.progress_behind")
          end
        end

      I18n.t(
        "daily_challenge.bot.commands.progress_message",
        challenge: challenge_link(challenge),
        done: done,
        needed: needed,
        time_remaining: time_remaining,
        status: status,
      )
    end

    def self.help_response(bot_username)
      I18n.t("daily_challenge.bot.commands.help", bot_username: bot_username)
    end

    def self.challenge_link(challenge)
      challenge.bot_link
    end
    private_class_method :challenge_link
  end
end
