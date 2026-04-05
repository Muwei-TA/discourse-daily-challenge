# frozen_string_literal: true

class DiscourseDailyChallenge::AdminDailyChallengesController < Admin::AdminController
  requires_plugin DiscourseDailyChallenge::PLUGIN_NAME

  skip_before_action :ensure_admin
  before_action :ensure_challenge_manager
  before_action :check_mod_access
  before_action :find_and_authorize_challenge, only: %i[show update destroy post_leaderboard drawing]

  def index
    challenges = DailyChallenge.includes(:topic).order(start_date: :desc)

    unless current_user.admin? || current_user.moderator?
      challenges = challenges.where(category_id: category_mod_category_ids)
    end

    render_serialized(challenges, DailyChallengeSerializer, root: "challenges")
  end

  def show
    render_serialized(@challenge, DailyChallengeSerializer, root: "challenge")
  end

  def create
    challenge = DailyChallenge.new(challenge_params)

    if params[:topic_id].present?
      topic = Topic.find_by(id: params[:topic_id])
      challenge.category_id = topic.category_id if topic
    end

    unless can_access_challenge_category?(challenge.category_id)
      return render_json_error(
               I18n.t("daily_challenge.errors.category_access_denied"),
               status: :unprocessable_entity,
             )
    end

    if challenge.award_badge && challenge.badge_name.blank?
      return render_json_error(
               I18n.t("daily_challenge.errors.badge_name_required"),
               status: :unprocessable_entity,
             )
    end

    if challenge.save
      sync_badge(challenge)
      render_serialized(challenge, DailyChallengeSerializer, root: "challenge")
    else
      render_json_error(challenge)
    end
  end

  def update
    @challenge.assign_attributes(challenge_params)

    if params[:topic_id].present?
      topic = Topic.find_by(id: params[:topic_id])
      @challenge.category_id = topic.category_id if topic
    end

    unless can_access_challenge_category?(@challenge.category_id)
      return render_json_error(
               I18n.t("daily_challenge.errors.category_access_denied"),
               status: :unprocessable_entity,
             )
    end

    if @challenge.award_badge && @challenge.badge_name.blank?
      return render_json_error(
               I18n.t("daily_challenge.errors.badge_name_required"),
               status: :unprocessable_entity,
             )
    end

    if @challenge.save
      sync_badge(@challenge)
      render_serialized(@challenge, DailyChallengeSerializer, root: "challenge")
    else
      render_json_error(@challenge)
    end
  end

  def destroy
    destroy_challenge_badge(@challenge)
    @challenge.destroy
    render json: success_json
  end

  def post_leaderboard
    DiscourseDailyChallenge::LeaderboardPoster.post_weekly_update(@challenge)
    render json: success_json
  rescue StandardError => e
    render_json_error(e.message)
  end

  def drawing
    min_checkins = [params[:min_checkins].to_i, 1].max

    scope = DailyCheckIn.where(challenge_id: @challenge.id)

    if params[:start_date].present?
      begin
        scope = scope.where("check_in_date >= ?", Date.parse(params[:start_date]))
      rescue ArgumentError
        return render_json_error("Invalid start_date", status: :unprocessable_entity)
      end
    end

    if params[:end_date].present?
      begin
        scope = scope.where("check_in_date <= ?", Date.parse(params[:end_date]))
      rescue ArgumentError
        return render_json_error("Invalid end_date", status: :unprocessable_entity)
      end
    end

    eligible_user_ids =
      scope.group(:user_id).having("COUNT(*) >= ?", min_checkins).pluck(:user_id)

    usernames = User.where(id: eligible_user_ids).order(:username).pluck(:username)

    render json: { usernames: usernames, count: usernames.size }
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

  def find_and_authorize_challenge
    @challenge = DailyChallenge.includes(:topic).find_by(id: params[:id])
    raise Discourse::NotFound unless @challenge

    unless can_access_challenge?(@challenge)
      return render json: { error: I18n.t("daily_challenge.errors.access_denied") },
                    status: :forbidden
    end
  end

  def can_access_challenge?(challenge)
    return true if current_user.admin?
    return true if current_user.moderator?

    return false if challenge.category_id.nil?
    category_mod_for_category?(current_user, challenge.category_id)
  end

  def can_access_challenge_category?(category_id)
    return true if current_user.admin?
    return true if current_user.moderator?

    category_id.present? && category_mod_category_ids.include?(category_id)
  end

  def category_mod?(user)
    ::CategoryModerationGroup.joins(group: :group_users).where(
      group_users: {
        user_id: user.id,
      },
    ).exists?
  end

  def category_mod_for_category?(user, category_id)
    ::CategoryModerationGroup.joins(group: :group_users).where(
      group_users: {
        user_id: user.id,
      },
      category_id: category_id,
    ).exists?
  end

  def category_mod_category_ids
    ::CategoryModerationGroup.joins(group: :group_users).where(
      group_users: {
        user_id: current_user.id,
      },
    ).distinct.pluck(:category_id)
  end

  def challenge_params
    params.permit(
      :topic_id,
      :hashtag,
      :start_date,
      :end_date,
      :check_ins_needed,
      :description,
      :weekly_post_enabled,
      :weekly_post_day,
      :weekly_post_hour,
      :award_badge,
      :badge_name,
      :challenge_timezone,
      :check_in_interval,
      :week_start,
      :reminder_dms_enabled,
    )
  end

  def sync_badge(challenge)
    if challenge.award_badge && challenge.badge_name.present?
      if challenge.badge_id
        badge = Badge.find_by(id: challenge.badge_id)
        if badge
          badge.update(name: challenge.badge_name, description: badge_description_for(challenge))
        else
          create_badge_for(challenge)
        end
      else
        create_badge_for(challenge)
      end
    elsif challenge.badge_id
      Badge.find_by(id: challenge.badge_id)&.destroy
      challenge.update_column(:badge_id, nil)
    end
  rescue StandardError => e
    Rails.logger.warn(
      "DailyChallenge: badge sync failed for challenge #{challenge.id}: #{e.message}",
    )
  end

  def create_badge_for(challenge)
    badge =
      Badge.create!(
        name: challenge.badge_name,
        description: badge_description_for(challenge),
        badge_type_id: BadgeType::Silver,
        allow_title: false,
        multiple_grant: false,
      )
    challenge.update_column(:badge_id, badge.id)
  end

  def badge_description_for(challenge)
    topic = Topic.find_by(id: challenge.topic_id)
    if topic
      I18n.t("daily_challenge.badge.description_with_topic", title: topic.title)
    else
      I18n.t("daily_challenge.badge.description_fallback")
    end
  end

  def destroy_challenge_badge(challenge)
    return unless challenge.badge_id
    Badge.find_by(id: challenge.badge_id)&.destroy
  end
end
