# frozen_string_literal: true

module DiscourseDailyChallenge
  class DmCommandHandler
    COMMANDS = %w[status leaderboard streak checkins progress help drawing].freeze
    CHALLENGE_COMMANDS = %w[leaderboard streak checkins progress drawing].freeze
    DRAWING_COMMANDS = %w[drawing].freeze
    PICKER_TTL = 5.minutes.to_i

    def self.handle(post)
      return unless SiteSetting.daily_challenge_enabled

      bot_username = SiteSetting.daily_challenge_bot_username.presence
      return unless bot_username

      bot = User.find_by(username: bot_username)
      return unless bot

      return unless post.topic&.archetype == Archetype.private_message
      return unless TopicAllowedUser.exists?(topic_id: post.topic_id, user_id: bot.id)
      return if post.user_id == bot.id
      return if post.post_type != Post.types[:regular]

      user = post.user
      return unless user

      raw = post.raw.to_s.strip

      picker_key = "daily_challenge:dm_picker:#{post.topic_id}:#{user.id}"
      pending_json = Discourse.redis.get(picker_key)

      if pending_json
        handle_picker_response(post, bot, user, bot_username, pending_json, picker_key, raw)
        return
      end

      command = raw.split.first.to_s.downcase
      return unless COMMANDS.include?(command)

      rate_key = "daily_challenge_bot_rate_limit:#{user.id}"
      count = Discourse.redis.incr(rate_key)
      Discourse.redis.expire(rate_key, 1.hour.to_i) if count == 1
      if count > 10
        reply(bot, post.topic_id, I18n.t("daily_challenge.bot.rate_limit_dm_body"))
        return
      end

      if command == "help"
        reply(bot, post.topic_id, MentionHandler.build_response("help", nil, user, bot_username))
        return
      end

      if command == "status"
        reply(bot, post.topic_id, MentionHandler.build_response("status", nil, user, bot_username))
        return
      end

      active_challenges = DailyChallenge.active.select(&:active?)

      if DRAWING_COMMANDS.include?(command)
        candidates =
          active_challenges.select { |c| user_can_access_challenge?(user, c) }

        if candidates.empty?
          reply(bot, post.topic_id, I18n.t("daily_challenge.bot.dm.drawing_no_access"))
          return
        end

        if candidates.size == 1
          reply(bot, post.topic_id, drawing_response(candidates.first, raw))
          return
        end

        Discourse.redis.set(
          picker_key,
          { command: command, command_raw: raw, challenge_ids: candidates.map(&:id) }.to_json,
          ex: PICKER_TTL,
        )

        reply(bot, post.topic_id, picker_prompt(command, candidates))
      else
        participated =
          active_challenges.select do |c|
            DailyCheckIn.where(challenge_id: c.id, user_id: user.id).exists?
          end

        if participated.empty?
          reply(bot, post.topic_id, I18n.t("daily_challenge.bot.dm.no_active_challenges"))
          return
        end

        if participated.size == 1
          reply(
            bot,
            post.topic_id,
            MentionHandler.build_response(command, participated.first, user, bot_username),
          )
          return
        end

        Discourse.redis.set(
          picker_key,
          { command: command, command_raw: raw, challenge_ids: participated.map(&:id) }.to_json,
          ex: PICKER_TTL,
        )

        reply(bot, post.topic_id, picker_prompt(command, participated))
      end
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge DmCommandHandler error for post #{post.id}: #{e.message}",
      )
    end

    def self.handle_picker_response(post, bot, user, bot_username, pending_json, picker_key, raw)
      pending = JSON.parse(pending_json)
      command = pending["command"]
      command_raw = pending["command_raw"].to_s
      challenge_ids = pending["challenge_ids"]

      challenges = DailyChallenge.where(id: challenge_ids).index_by(&:id)
      ordered = challenge_ids.filter_map { |id| challenges[id] }

      if raw.downcase == "a"
        Discourse.redis.del(picker_key)
        responses =
          if DRAWING_COMMANDS.include?(command)
            ordered.map { |c| drawing_response(c, command_raw) }
          else
            ordered.map { |c| MentionHandler.build_response(command, c, user, bot_username) }
          end
        reply(bot, post.topic_id, responses.join("\n\n---\n\n"))
        return
      end

      idx = raw.to_i
      if idx >= 1 && idx <= ordered.size
        Discourse.redis.del(picker_key)
        response =
          if DRAWING_COMMANDS.include?(command)
            drawing_response(ordered[idx - 1], command_raw)
          else
            MentionHandler.build_response(command, ordered[idx - 1], user, bot_username)
          end
        reply(bot, post.topic_id, response)
        return
      end

      reply(bot, post.topic_id, picker_invalid(command, ordered))
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge DmCommandHandler picker error for post #{post.id}: #{e.message}",
      )
    end

    def self.drawing_response(challenge, raw_command)
      parts = raw_command.split
      min_checkins = [parts[1].to_i, 1].max
      start_date = parse_date(parts[2])
      end_date = parse_date(parts[3])

      scope = DailyCheckIn.where(challenge_id: challenge.id)
      scope = scope.where("check_in_date >= ?", start_date) if start_date
      scope = scope.where("check_in_date <= ?", end_date) if end_date

      eligible_user_ids =
        scope.group(:user_id).having("COUNT(*) >= ?", min_checkins).pluck(:user_id)

      usernames = User.where(id: eligible_user_ids).order(:username).pluck(:username)

      count_text = I18n.t("daily_challenge.bot.dm.drawing_count", count: usernames.size)

      if usernames.empty?
        return I18n.t(
                 "daily_challenge.bot.dm.drawing_none",
                 challenge: challenge_label(challenge),
                 min_checkins: min_checkins,
               )
      end

      "#{usernames.map { |u| "@#{u}" }.join("\n")}\n\n#{count_text}"
    end

    def self.user_can_access_challenge?(user, challenge)
      return true if user.admin?
      return true if user.moderator?
      return false if challenge.category_id.nil?
      ::CategoryModerationGroup.joins(group: :group_users).where(
        group_users: {
          user_id: user.id,
        },
        category_id: challenge.category_id,
      ).exists?
    end

    def self.parse_date(str)
      return nil if str.blank?
      Date.parse(str)
    rescue ArgumentError
      nil
    end

    def self.picker_prompt(command, challenges)
      lines = challenges.each_with_index.map { |c, i| "#{i + 1}. #{challenge_label(c)}" }
      I18n.t(
        "daily_challenge.bot.dm.picker_prompt",
        command: command,
        challenges: lines.join("\n"),
      )
    end

    def self.picker_invalid(command, challenges)
      lines = challenges.each_with_index.map { |c, i| "#{i + 1}. #{challenge_label(c)}" }
      I18n.t(
        "daily_challenge.bot.dm.picker_invalid",
        command: command,
        challenges: lines.join("\n"),
      )
    end

    def self.challenge_label(challenge)
      challenge.topic&.title || "##{challenge.hashtag}"
    end

    def self.reply(bot, topic_id, raw)
      PostCreator.create!(
        bot,
        topic_id: topic_id,
        raw: raw,
        skip_validations: true,
      )
    end

    private_class_method :drawing_response,
                         :user_can_access_challenge?,
                         :parse_date,
                         :picker_prompt,
                         :picker_invalid,
                         :challenge_label,
                         :reply
  end
end
