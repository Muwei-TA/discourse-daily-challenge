# frozen_string_literal: true

class DiscourseDailyChallenge::AdminDailyDashboardController < Admin::AdminController
  requires_plugin DiscourseDailyChallenge::PLUGIN_NAME

  skip_before_action :ensure_admin
  before_action :ensure_challenge_manager
  before_action :check_mod_access

  def show
    today = Date.current

    active_scope = DailyChallenge.active.includes(:topic, check_ins: :user)
    archived_scope =
      DailyChallenge.where("end_date < ?", today).includes(:topic).order(end_date: :desc)

    unless current_user.admin? || current_user.moderator?
      cat_ids = category_mod_category_ids
      active_scope = active_scope.where(category_id: cat_ids)
      archived_scope = archived_scope.where(category_id: cat_ids)
    end

    active_challenges = active_scope.select(&:active?)

    archived_batch = archived_scope.limit(51).to_a
    archived_has_more = archived_batch.size == 51
    archived_challenges = archived_batch.first(50)

    render json: {
             active_challenges: active_challenges.map { |c| serialize_active_challenge(c) },
             archived_challenges: archived_challenges.map { |c| serialize_archived_challenge(c) },
             archived_has_more: archived_has_more,
           }
  end

  private

  def ensure_challenge_manager
    return if current_user&.admin?
    return if current_user&.moderator?
    return if SiteSetting.daily_challenge_category_mod_access_enabled && category_mod?(current_user)
    raise Discourse::InvalidAccess
  end

  def check_mod_access
    return if current_user.admin?
    return if SiteSetting.daily_challenge_mod_access_enabled
    return if category_mod?(current_user)

    render json: { error: I18n.t("daily_challenge.errors.access_denied") }, status: :forbidden
  end

  def category_mod?(user)
    ::CategoryModerationGroup.joins(group: :group_users).where(
      group_users: {
        user_id: user.id,
      },
    ).exists?
  end

  def category_mod_category_ids
    ::CategoryModerationGroup.joins(group: :group_users).where(
      group_users: {
        user_id: current_user.id,
      },
    ).distinct.pluck(:category_id)
  end

  def serialize_active_challenge(challenge)
    check_ins_by_user = challenge.check_ins.group_by(&:user_id)

    leaderboard =
      check_ins_by_user
        .filter_map do |user_id, check_ins|
          user = check_ins.first.user
          next unless user

          dates = check_ins.map { |ci| ci.check_in_date.to_date }.sort.uniq
          {
            user_id: user_id,
            username: user.username,
            avatar_template: user.avatar_template,
            total_check_ins: dates.size,
            streak: calculate_streak(dates, challenge),
            completion_pct: completion_pct(dates.size, challenge.check_ins_needed),
            check_in_dates: dates.map(&:iso8601),
          }
        end
        .sort_by { |e| -e[:total_check_ins] }
        .each_with_index
        .map { |e, i| e.merge(rank: i + 1) }

    total = leaderboard.size
    avg_check_ins =
      total > 0 ? (leaderboard.sum { |e| e[:total_check_ins] }.to_f / total).round(1) : 0

    {
      challenge: {
        id: challenge.id,
        hashtag: challenge.display_tag,
        check_ins_needed: challenge.check_ins_needed,
        start_date: challenge.start_date.iso8601,
        end_date: challenge.end_date.iso8601,
        elapsed_days: challenge.elapsed_days,
        total_days: (challenge.end_date - challenge.start_date).to_i + 1,
        topic_url: challenge.destination_topic&.relative_url,
        topic_title: challenge.display_name,
        check_in_interval: challenge.check_in_interval,
      },
      leaderboard: leaderboard,
      stats: {
        total_participants: total,
        avg_check_ins: avg_check_ins,
        progress_pct: challenge_progress_pct(challenge),
      },
    }
  end

  def serialize_archived_challenge(challenge)
    counts_by_user = challenge.check_ins.group(:user_id).count
    total = counts_by_user.size
    completed = counts_by_user.count { |_, count| count >= challenge.check_ins_needed }
    completion_rate = total > 0 ? ((completed.to_f / total) * 100).round(1) : 0

    winner = nil
    if counts_by_user.any?
      winner_id, winner_count = counts_by_user.max_by { |_, c| c }
      winner_user = User.find_by(id: winner_id)
      if winner_user
        winner = {
          username: winner_user.username,
          avatar_template: winner_user.avatar_template,
          total_check_ins: winner_count,
        }
      end
    end

    {
      id: challenge.id,
      hashtag: challenge.display_tag,
      start_date: challenge.start_date.iso8601,
      end_date: challenge.end_date.iso8601,
      topic_title: challenge.display_name,
      topic_url: challenge.destination_topic&.relative_url,
      total_participants: total,
      winner: winner,
      completion_rate: completion_rate,
    }
  end

  def completion_pct(check_ins, needed)
    return 0 if needed <= 0
    ((check_ins.to_f / needed) * 100).round(1)
  end

  def challenge_progress_pct(challenge)
    total_days = (challenge.end_date - challenge.start_date).to_i + 1 # end_date inclusive
    return 0 if total_days <= 0
    ((challenge.elapsed_days.to_f / total_days) * 100).round(1)
  end

  def calculate_streak(sorted_dates, challenge)
    if challenge.check_in_interval == "weekly"
      calculate_weekly_streak(sorted_dates, challenge)
    else
      calculate_daily_streak(sorted_dates, challenge.local_date)
    end
  end

  def calculate_daily_streak(sorted_dates, today)
    return 0 if sorted_dates.empty?

    return 0 if sorted_dates.last < today - 1

    streak = 0
    expected = [sorted_dates.last, today].min

    sorted_dates.reverse_each do |date|
      break if date != expected
      streak += 1
      expected -= 1
    end

    streak
  end

  def calculate_weekly_streak(sorted_dates, challenge)
    return 0 if sorted_dates.empty?

    tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
    today = Time.now.in_time_zone(tz).to_date
    wday = DiscourseDailyChallenge::ChallengeUtils.week_start_wday(challenge)

    current_week_start = DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(today, wday)
    latest_week_start =
      DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(sorted_dates.last, wday)

    # Streak is broken if the most recent check-in was more than one week ago
    # (mirrors the daily logic: grace period of one period back)
    return 0 if latest_week_start < current_week_start - 7

    checked_weeks =
      sorted_dates
        .map { |d| DiscourseDailyChallenge::ChallengeUtils.week_start_for_date(d, wday) }
        .to_set

    streak = 0
    week = [latest_week_start, current_week_start].min

    loop do
      break unless checked_weeks.include?(week)
      streak += 1
      week -= 7
    end

    streak
  end
end
