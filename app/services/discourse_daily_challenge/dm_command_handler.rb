# frozen_string_literal: true

module DiscourseDailyChallenge
  class DmCommandHandler
    COMMANDS = %w[status leaderboard streak checkins progress help].freeze
    CHALLENGE_COMMANDS = %w[leaderboard streak checkins progress].freeze
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
        { command: command, challenge_ids: participated.map(&:id) }.to_json,
        ex: PICKER_TTL,
      )

      reply(bot, post.topic_id, picker_prompt(command, participated))
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge DmCommandHandler error for post #{post.id}: #{e.message}",
      )
    end

    def self.handle_picker_response(post, bot, user, bot_username, pending_json, picker_key, raw)
      pending = JSON.parse(pending_json)
      command = pending["command"]
      challenge_ids = pending["challenge_ids"]

      challenges = DailyChallenge.where(id: challenge_ids).index_by(&:id)
      ordered = challenge_ids.filter_map { |id| challenges[id] }

      if raw.downcase == "a"
        Discourse.redis.del(picker_key)
        responses =
          ordered.map { |c| MentionHandler.build_response(command, c, user, bot_username) }
        reply(bot, post.topic_id, responses.join("\n\n---\n\n"))
        return
      end

      idx = raw.to_i
      if idx >= 1 && idx <= ordered.size
        Discourse.redis.del(picker_key)
        reply(
          bot,
          post.topic_id,
          MentionHandler.build_response(command, ordered[idx - 1], user, bot_username),
        )
        return
      end

      reply(bot, post.topic_id, picker_invalid(command, ordered))
    rescue StandardError => e
      Rails.logger.error(
        "DailyChallenge DmCommandHandler picker error for post #{post.id}: #{e.message}",
      )
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

    private_class_method :picker_prompt, :picker_invalid, :challenge_label, :reply
  end
end
