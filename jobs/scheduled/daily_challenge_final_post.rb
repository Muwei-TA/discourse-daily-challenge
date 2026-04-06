# frozen_string_literal: true

module Jobs
  class DailyChallengeFinalPost < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.daily_challenge_enabled

      # Cast a ±1-day net in UTC so no challenge is missed due to timezone
      # offsets, then do a precise per-challenge timezone check in Ruby.
      yesterday_utc = Date.current - 1

      DailyChallenge
        .where(
          end_date: (yesterday_utc - 1)..(yesterday_utc + 1),
          final_post_sent: false,
        )
        .includes(:topic)
        .find_each do |challenge|
          tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
          local_yesterday = Time.now.in_time_zone(tz).to_date - 1
          next unless challenge.end_date == local_yesterday
          post_final_results(challenge)
        rescue StandardError => e
          Rails.logger.error(
            "DailyChallengeFinalPost error for challenge #{challenge.id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}",
          )
        end
    end

    private

    def post_final_results(challenge)
      topic = challenge.topic
      return unless topic

      counts_by_user = challenge.check_ins.group(:user_id).order("count_all DESC").count
      eligible = compute_eligible(challenge, counts_by_user)

      poster = DiscourseDailyChallenge.bot_user || Discourse.system_user

      PostCreator.create!(
        poster,
        topic_id: topic.id,
        raw: build_final_post_body(challenge, eligible, counts_by_user.size),
        skip_validations: true,
        skip_guardian: true,
      )

      award_badges(challenge, eligible)
      challenge.update_column(:final_post_sent, true)
    end

    def compute_eligible(challenge, counts_by_user)
      counts_by_user
        .select { |_user_id, count| count >= challenge.check_ins_needed }
        .filter_map do |user_id, count|
          user = User.find_by(id: user_id)
          next unless user
          { user: user, count: count }
        end
    end

    def award_badges(challenge, eligible)
      return unless challenge.award_badge && challenge.badge_id

      badge = Badge.find_by(id: challenge.badge_id)
      return unless badge

      eligible.each do |entry|
        BadgeGranter.grant(badge, entry[:user], granted_by: Discourse.system_user)
      rescue StandardError => e
        Rails.logger.error(
          "DailyChallenge badge grant error for user #{entry[:user].id}: #{e.message}",
        )
      end
    end

    def build_final_post_body(challenge, eligible, total_participants)
      completed = eligible.size

      lines = []
      lines << "## #{challenge.topic.title} — Final Results 🏆"
      lines << ""
      lines << I18n.t("daily_challenge.final_post.intro", hashtag: challenge.hashtag)
      lines << ""

      if eligible.any?
        lines << I18n.t("daily_challenge.final_post.eligible_header")
        lines << ""
        eligible.each_with_index do |entry, idx|
          medal = %w[🥇 🥈 🥉][idx]
          prefix = medal ? "#{medal} " : ""
          lines << I18n.t(
            "daily_challenge.final_post.row",
            medal: prefix,
            username: entry[:user].username,
            count: entry[:count],
          )
        end
        lines << ""
        lines << I18n.t("daily_challenge.final_post.congrats")
      else
        lines << I18n.t(
          "daily_challenge.final_post.no_completions",
          needed: challenge.check_ins_needed,
        )
      end

      lines << ""
      lines << I18n.t(
        "daily_challenge.final_post.summary",
        completed: completed,
        total: total_participants,
        needed: challenge.check_ins_needed,
      )

      lines.join("\n")
    end
  end
end
