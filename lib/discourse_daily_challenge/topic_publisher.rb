# frozen_string_literal: true

module DiscourseDailyChallenge
  module TopicPublisher
    def self.publish_today(challenge)
      I18n.with_locale(SiteSetting.default_locale) { publish_today_in_locale(challenge) }
    end

    def self.publish_today_in_locale(challenge)
      return unless challenge.daily_topics_enabled? && challenge.active?
      date = challenge.local_date
      body = I18n.t("daily_challenge.daily_topic.body", name: challenge.display_name,
                    date: date.iso8601, timezone: challenge.challenge_timezone,
                    tag: challenge.tag&.name, url: challenge.topics_url,
                    needed: challenge.check_ins_needed)
      publish(challenge, "daily", date,
              I18n.t("daily_challenge.daily_topic.title", name: challenge.display_name, date: date.iso8601), body)
    end

    def self.publish(challenge, kind, date, title, raw)
      publication = nil
      challenge.with_lock do
        next if kind == "daily" && (!challenge.active? || date != challenge.local_date)
        publication = challenge.publications.find_by(kind: kind, publication_date: date)
        if publication
          raise "Published topic #{publication.topic_id} has been removed" unless publication.topic && !publication.topic.trashed?
          next
        end
        bot = DiscourseDailyChallenge.bot_user
        raise "Configure an active Daily challenge bot username" unless bot&.active? && bot.approved? && !bot.suspended?
        guardian = Guardian.new(bot)
        raise "Bot cannot create topics in the challenge category" unless challenge.category && guardian.can_create_topic_on_category?(challenge.category)
        raise "Challenge tag is missing or tagging is disabled" unless challenge.tag && SiteSetting.tagging_enabled
        TagManager.validate_category!(challenge.tag, challenge.category, guardian)
        post = PostCreator.create!(bot, title: title.truncate(SiteSetting.max_topic_title_length), raw: raw, category: challenge.category_id,
                                  tags: [{ id: challenge.tag_id }],
                                  skip_validations: true)
        unless post.topic.tags.exists?(id: challenge.tag_id)
          raise "Published topic did not retain the configured tag"
        end
        publication = challenge.publications.create!(kind: kind, publication_date: date, topic_id: post.topic_id)
        challenge.update_columns(publication_error: nil, publication_error_at: nil)
      end
      publication
    rescue StandardError => e
      challenge.update_columns(publication_error: e.message.truncate(1000), publication_error_at: Time.current)
      Rails.logger.error("DailyChallenge publication failed (#{challenge.id}, #{kind}, #{date}): #{e.message}")
      raise
    end
  end
end
