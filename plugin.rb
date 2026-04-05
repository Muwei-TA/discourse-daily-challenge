# frozen_string_literal: true

# name: discourse-daily-challenge
# about: Run time-limited daily challenges on your Discourse forum. Participants check in by posting with a hashtag or uploading a photo. Admins get a real-time leaderboard dashboard, automated weekly progress posts, and a final results post with optional badge awards.
# version: 1.5.2
# authors: R23D Printing
# url: https://gitlab.com/r23dprinting-group/discourse-daily-challenge
# required_version: 2.7.0

enabled_site_setting :daily_challenge_enabled

register_svg_icon "dumbbell"
register_svg_icon "fire"
register_svg_icon "medal"

module ::DiscourseDailyChallenge
  PLUGIN_NAME = "discourse-daily-challenge"
end

require_relative "lib/discourse_daily_challenge/engine"
require_relative "lib/discourse_daily_challenge/challenge_manager_constraint"

after_initialize do
  def DiscourseDailyChallenge.bot_user
    username = SiteSetting.daily_challenge_bot_username.presence
    return nil unless username
    User.find_by(username: username)
  end

  add_admin_route(
    "daily_challenge.admin.title",
    "discourse-daily-challenge",
    { use_new_show_route: true },
  )

  require_relative "app/models/daily_challenge"
  require_relative "app/models/daily_check_in"
  require_relative "app/serializers/daily_challenge_serializer"
  require_relative "app/serializers/daily_check_in_serializer"
  require_relative "app/controllers/discourse_daily_challenge/admin_daily_challenges_controller"
  require_relative "app/controllers/discourse_daily_challenge/admin_daily_check_ins_controller"
  require_relative "app/controllers/discourse_daily_challenge/admin_daily_dashboard_controller"
  require_relative "lib/discourse_daily_challenge/challenge_utils"
  require_relative "lib/discourse_daily_challenge/leaderboard_poster"
  require_relative "lib/discourse_daily_challenge/check_in_service"
  require_relative "app/services/discourse_daily_challenge/mention_handler"
  require_relative "app/services/discourse_daily_challenge/dm_command_handler"
  require_relative "jobs/scheduled/daily_challenge_weekly_post"
  require_relative "jobs/scheduled/daily_challenge_final_post"
  require_relative "app/jobs/scheduled/discourse_daily_challenge_send_reminders"
  require_relative "app/jobs/regular/discourse_daily_challenge_send_checkin_dm"
  require_relative "app/jobs/regular/discourse_daily_challenge_send_completion_dm"

  add_to_serializer(:current_user, :is_challenge_manager) do
    ::CategoryModerationGroup.joins(group: :group_users).where(group_users: { user_id: object.id }).exists?
  end

  on(:post_created) do |post, _opts, user|
    next unless SiteSetting.daily_challenge_enabled
    next if post.post_type != Post.types[:regular]
    next if user.nil? || user.anonymous?

    DiscourseDailyChallenge::CheckInService.process(post)
  end

  on(:post_created) do |post|
    next unless SiteSetting.daily_challenge_enabled
    DiscourseDailyChallenge::MentionHandler.handle(post)
    DiscourseDailyChallenge::DmCommandHandler.handle(post)
  end

  on(:post_revised) do |post|
    next unless SiteSetting.daily_challenge_enabled
    next if post.post_type != Post.types[:regular]
    user = post.user
    next if user.nil? || user.anonymous?
    DiscourseDailyChallenge::CheckInService.process_edit(post)
  end
end
