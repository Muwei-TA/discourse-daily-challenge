# frozen_string_literal: true

class DailyChallenge < ActiveRecord::Base
  self.table_name = "daily_challenges"
  self.ignored_columns = ["num_days"]

  belongs_to :topic
  has_many :check_ins,
           class_name: "DailyCheckIn",
           foreign_key: :challenge_id,
           dependent: :destroy

  CHECK_IN_SCOPES = %w[topic topic_tag site_hashtag].freeze

  before_validation :normalize_scope_tag

  validates :topic_id, presence: true, uniqueness: true
  validates :check_in_scope, inclusion: { in: CHECK_IN_SCOPES }
  validates :scope_tag, presence: true, if: :topic_tag_scope?
  validates :scope_tag,
            length: { maximum: 100 },
            format: { with: /\A[[:alnum:]_-]+\z/ },
            allow_blank: true
  validates :hashtag,
            presence: true,
            format: {
              with: /\A\w+\z/,
              message: "only letters, digits, and underscores allowed",
            }
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

  def active?
    tz = ActiveSupport::TimeZone[challenge_timezone] || Time.zone
    local_today = Time.now.in_time_zone(tz).to_date
    local_today >= start_date && local_today <= end_date
  end

  def topic_tag_scope?
    check_in_scope == "topic_tag"
  end

  def normalize_scope_tag
    self.scope_tag = scope_tag.to_s.strip.downcase.presence
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
