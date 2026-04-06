# frozen_string_literal: true

DiscourseDailyChallenge::Engine.routes.draw do
  # no engine routes needed
end

Discourse::Application.routes.draw do
  scope "/admin/plugins/discourse-daily-challenge",
        constraints: StaffConstraint.new do
    get "/challenges" =>
          "discourse_daily_challenge/admin_daily_challenges#index",
        as: :daily_challenge_admin_challenges
    post "/challenges" =>
           "discourse_daily_challenge/admin_daily_challenges#create"
    get "/challenges/:id" =>
          "discourse_daily_challenge/admin_daily_challenges#show"
    put "/challenges/:id" =>
          "discourse_daily_challenge/admin_daily_challenges#update"
    delete "/challenges/:id" =>
             "discourse_daily_challenge/admin_daily_challenges#destroy"
    post "/challenges/:id/post_leaderboard" =>
           "discourse_daily_challenge/admin_daily_challenges#post_leaderboard"
    get "/challenges/:id/drawing" =>
          "discourse_daily_challenge/admin_daily_challenges#drawing"

    get "/challenges/:challenge_id/check_ins" =>
          "discourse_daily_challenge/admin_daily_check_ins#index"
    post "/challenges/:challenge_id/check_ins" =>
           "discourse_daily_challenge/admin_daily_check_ins#create"
    delete "/challenges/:challenge_id/check_ins/:id" =>
             "discourse_daily_challenge/admin_daily_check_ins#destroy"

    get "/dashboard" => "discourse_daily_challenge/admin_daily_dashboard#show"
  end

  scope "/challenges",
        constraints: DiscourseDailyChallenge::ChallengeManagerConstraint.new do
    get "/dashboard" =>
          "discourse_daily_challenge/admin_daily_dashboard#show",
        as: :daily_challenge_challenges_dashboard
    get "/challenges" =>
          "discourse_daily_challenge/admin_daily_challenges#index",
        as: :daily_challenge_challenges_index
    post "/challenges" =>
           "discourse_daily_challenge/admin_daily_challenges#create"
    get "/challenges/:id" =>
          "discourse_daily_challenge/admin_daily_challenges#show",
        as: :daily_challenge_challenges_show
    put "/challenges/:id" =>
          "discourse_daily_challenge/admin_daily_challenges#update"
    delete "/challenges/:id" =>
             "discourse_daily_challenge/admin_daily_challenges#destroy"
    post "/challenges/:id/post_leaderboard" =>
           "discourse_daily_challenge/admin_daily_challenges#post_leaderboard"
    get "/challenges/:id/drawing" =>
          "discourse_daily_challenge/admin_daily_challenges#drawing"

    get "/challenges/:challenge_id/check_ins" =>
          "discourse_daily_challenge/admin_daily_check_ins#index"
    post "/challenges/:challenge_id/check_ins" =>
           "discourse_daily_challenge/admin_daily_check_ins#create"
    delete "/challenges/:challenge_id/check_ins/:id" =>
             "discourse_daily_challenge/admin_daily_check_ins#destroy"
  end
end
