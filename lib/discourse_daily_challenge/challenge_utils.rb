# frozen_string_literal: true

module DiscourseDailyChallenge
  module ChallengeUtils
    # Returns the Ruby Date#wday value (0=Sun, 1=Mon … 6=Sat) for the
    # configured week_start of a challenge.
    def self.week_start_wday(challenge)
      case challenge.week_start
      when "sunday"
        0
      when "saturday"
        6
      else
        1 # monday (default)
      end
    end

    # Returns the date of the first day of the calendar week that contains
    # +date+, where the week boundary is defined by +week_start_wday+.
    def self.week_start_for_date(date, week_start_wday)
      days_since_start = (date.wday - week_start_wday) % 7
      date - days_since_start
    end

    # Returns the current streak (consecutive periods ending at or near today)
    # for a given user in a given challenge.
    def self.user_streak(challenge, user_id)
      dates =
        DailyCheckIn
          .where(challenge_id: challenge.id, user_id: user_id)
          .order(check_in_date: :asc)
          .pluck(:check_in_date)
          .map(&:to_date)
          .uniq
      return 0 if dates.empty?

      if challenge.check_in_interval == "weekly"
        user_weekly_streak(challenge, dates)
      else
        user_daily_streak(dates, challenge.local_date)
      end
    end

    def self.user_daily_streak(sorted_dates, today = Date.current)
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

    def self.user_weekly_streak(challenge, sorted_dates)
      return 0 if sorted_dates.empty?

      tz = ActiveSupport::TimeZone[challenge.challenge_timezone] || Time.zone
      today = Time.now.in_time_zone(tz).to_date
      wday = week_start_wday(challenge)
      current_week_start = week_start_for_date(today, wday)
      latest_week_start = week_start_for_date(sorted_dates.last, wday)

      return 0 if latest_week_start < current_week_start - 7

      checked_weeks =
        sorted_dates.map { |d| week_start_for_date(d, wday) }.to_set

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
end
