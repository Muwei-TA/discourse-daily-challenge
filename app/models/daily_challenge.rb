# frozen_string_literal: true

class DailyChallenge < ActiveRecord::Base
  self.table_name = "daily_challenges"
  self.ignored_columns = ["num_days"]

  belongs_to :topic, optional: true
  belongs_to :tag, optional: true
  belongs_to :category, optional: true
  has_many :publications, class_name: "DailyChallengeTopic", foreign_key: :challenge_id,
                         dependent: :destroy

  validates :name, :category, :tag, presence: true, if: :daily_topics_enabled?
  validates :name, length: { maximum: 180 }, allow_blank: true
  validates :check_in_interval, inclusion: { in: ["daily"] }, if: :daily_topics_enabled?
  has_many :check_ins,
           class_name: "DailyCheckIn",
           foreign_key: :challenge_id,
           dependent: :destroy

  validates :topic_id, presence: true, uniqueness: true, unless: :daily_topics_enabled?
  validates :hashtag,
            presence: true,
            format: {
              with: /\A\w+\z/,
              message: "only letters, digits, and underscores allowed",
            }, unless: :daily_topics_enabled?
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :check_ins_needed,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than: 0,
              less_than_or_equal_to: 365,
            }
  validates :weekly_post_day,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 6,
            }
  validates :weekly_post_hour,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 23,
            }
  validates :check_in_interval, inclusion: { in: %w[daily weekly] }
  validates :week_start, inclusion: { in: %w[sunday monday saturday] }, allow_nil: true
  validates :badge_name, presence: true, if: :award_badge?
  validates :badge_name, length: { maximum: 100 }, allow_blank: true
  validates :challenge_timezone,
            inclusion: {
              in: ActiveSupport::TimeZone.all.map(&:name),
              message: "is not a valid timezone",
            }

  validate :end_date_after_start_date

  scope :active, -> {
    today = Date.current
    # ±1 day buffer so challenges in timezones offset from UTC are not
    # prematurely excluded or included at date boundaries.
    # end_date is inclusive, so a challenge is still active on end_date itself.
    where("start_date <= ? AND end_date >= ?", today + 1, today - 1)
  }

  def local_date(time = Time.current)
    time.in_time_zone(ActiveSupport::TimeZone[challenge_timezone] || Time.zone).to_date
  end

  def display_name
    name.presence || topic&.title || "##{hashtag}"
  end

  def display_tag
    daily_topics_enabled? ? tag&.name : hashtag
  end

  def today_topic
    daily_topics_enabled? ? publications.find_by(kind: "daily", publication_date: local_date)&.topic : topic
  end

  def destination_topic
    today_topic || publications.where(kind: "daily").order(publication_date: :desc).first&.topic || topic
  end

  def topics_url
    tag&.url
  end

  def bot_link
    target = daily_topics_enabled? && active? ? today_topic : destination_topic
    url = target&.url || (daily_topics_enabled? ? "#{Discourse.base_url}/daily-challenges" : topics_url)
    url ? "[**#{display_name}**](#{url})" : "**#{display_name}**"
  end

  def active?
    tz = ActiveSupport::TimeZone[challenge_timezone] || Time.zone
    local_today = Time.now.in_time_zone(tz).to_date
    local_today >= start_date && local_today <= end_date
  end

  def end_date_after_start_date
    return unless start_date.present? && end_date.present?
    errors.add(:end_date, "must be after start date") if end_date <= start_date
  end

  def elapsed_days
    tz = ActiveSupport::TimeZone[challenge_timezone] || Time.zone
    local_today = Time.now.in_time_zone(tz).to_date
    return 0 if local_today < start_date
    total = (end_date - start_date).to_i + 1 # end_date inclusive
    [(local_today - start_date).to_i + 1, total].min
  end
end
