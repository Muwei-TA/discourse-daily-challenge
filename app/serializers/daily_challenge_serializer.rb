# frozen_string_literal: true

class DailyChallengeSerializer < ApplicationSerializer
  attributes :id,
             :topic_id,
             :topic_url,
             :topic_title,
             :hashtag,
             :start_date,
             :end_date,
             :check_ins_needed,
             :description,
             :active,
             :elapsed_days,
             :participant_count,
             :leaderboard,
             :weekly_post_enabled,
             :weekly_post_day,
             :weekly_post_hour,
             :award_badge,
             :badge_name,
             :badge_id,
             :challenge_timezone,
             :check_in_interval,
             :week_start,
             :category_id,
             :reminder_dms_enabled,
             :welcome_message

  def topic_url
    object.topic&.relative_url
  end

  def topic_title
    object.topic&.title
  end

  def active
    object.active?
  end

  def elapsed_days
    object.elapsed_days
  end

  def participant_count
    object.check_ins.select(:user_id).distinct.count
  end

  def leaderboard
    top = object.check_ins.group(:user_id).order("count_all DESC").count.first(10)
    users_by_id = User.where(id: top.map(&:first)).index_by(&:id)

    top.filter_map do |user_id, count|
      user = users_by_id[user_id]
      next unless user
      {
        user_id: user_id,
        username: user.username,
        name: user.name.presence || user.username,
        avatar_template: user.avatar_template,
        check_in_count: count,
      }
    end
  end
end
