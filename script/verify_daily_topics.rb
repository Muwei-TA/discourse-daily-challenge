# frozen_string_literal: true
# Run only against an isolated stage database:
# RAILS_ENV=production bundle exec rails runner plugins/discourse-daily-challenge/script/verify_daily_topics.rb
abort 'Refusing to create fixtures outside an .invalid stage host' unless Discourse.current_hostname.end_with?('.invalid')
require 'active_support/testing/time_helpers'
include ActiveSupport::Testing::TimeHelpers
SiteSetting.disable_emails = 'yes'
SiteSetting.tagging_enabled = true
SiteSetting.default_locale = 'zh_CN'
Jobs.run_later!
I18n.locale = :zh_CN
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results = []
def check(results, name)
  raise "FAIL: #{name}" unless yield
  results << name
  puts "PASS #{name}"
end
suffix = SecureRandom.hex(4)
make_user = lambda do |label, **attributes|
  User.create!({ username: "dc_#{label}_#{suffix}", email: "#{label}.#{suffix}@example.invalid",
                 active: true, approved: true, trust_level: 4 }.merge(attributes))
end
admin = make_user.call('admin', admin: true)
bot = make_user.call('bot')
user = make_user.call('member')
user.user_option.update!(timezone: 'America/Los_Angeles')
SiteSetting.daily_challenge_bot_username = bot.username
category = Category.find(4)
today = Time.current.in_time_zone('Beijing').to_date
make_challenge = lambda do |label, tag|
  DailyChallenge.create!(name: "#{label} #{suffix}", category: category, tag: tag,
                        daily_topics_enabled: true, hashtag: 'legacy_unused',
                        start_date: today - 1, end_date: today + 2, challenge_timezone: 'Beijing',
                        check_ins_needed: 2, award_badge: false)
end
first = nil
['中文签到', '📚', '阅读打卡📚', '👍🏽', '👩‍💻'].each do |label|
  tag = DiscourseDailyChallenge::TagManager.resolve!(label, Guardian.new(admin))
  challenge = make_challenge.call(label, tag)
  publication = I18n.with_locale(:en) { DiscourseDailyChallenge::TopicPublisher.publish_today(challenge) }
  check(results, "#{label}: exact tag persisted and assigned") { tag.reload.name == label && publication.topic.tags.exists?(id: tag.id) }
  check(results, "#{label}: bot author and midnight date") { publication.topic.user_id == bot.id && publication.publication_date == today }
  check(results, "#{label}: canonical tag filter URL uses ID") { tag.url.end_with?("/#{tag.id}") }
  first ||= challenge
end
publisher = DiscourseDailyChallenge::TopicPublisher
publication = first.publications.find_by!(kind: 'daily', publication_date: today)
check(results, 'publisher uses site locale outside a web request') { publication.topic.title.end_with?('打卡') && publication.topic.first_post.raw.include?('无须填写') }
check(results, 'activity does not require topic_id') { first.topic_id.nil? }
check(results, 'repeat publication returns same topic') { publisher.publish_today(first).id == publication.id }
reply = lambda do |raw, target = publication.topic_id, author = user|
  PostCreator.create!(author, topic_id: target, raw: raw, skip_validations: true)
end
normal = reply.call('普通文字，今天也坚持学习。')
check(results, 'ordinary reply creates check-in without hashtag or image') { first.check_ins.where(user_id: user.id).count == 1 }
check(results, 'activity timezone determines check-in date') { first.check_ins.find_by!(user_id: user.id).check_in_date == today }
reply.call('#legacy_unused 再次回复')
check(results, 'duplicate replies count once') { first.check_ins.where(user_id: user.id).count == 1 }
reply.call('Bot status announcement', publication.topic_id, bot)
check(results, 'configured bot never checks in') { first.check_ins.where(user_id: bot.id).count == 0 }
check(results, 'first post never checks in') { first.check_ins.where(post_id: publication.topic.first_post.id).none? }
other = PostCreator.create!(admin, title: "Other tagged topic #{suffix}", raw: 'This topic is not a daily publication.', category: category.id, tags: [first.tag.name], skip_validations: true)
reply.call('Not a check-in here', other.topic_id, admin)
check(results, 'unregistered topic with same tag is ignored') { first.check_ins.where(user_id: admin.id).none? }
DiscourseDailyChallenge::LeaderboardPoster.post_weekly_update(first)
weekly = first.publications.find_by!(kind: 'weekly')
reply.call('Replies on leaderboard do not count', weekly.topic_id, admin)
check(results, 'weekly report is separate and not a check-in') { weekly.topic_id != publication.topic_id && first.check_ins.where(user_id: admin.id).none? }
DiscourseDailyChallenge::LeaderboardPoster.post_weekly_update(first)
check(results, 'weekly report idempotency') { first.publications.where(kind: 'weekly').count == 1 }
# Removing the configured tag immediately prevents subsequent automatic check-ins.
publication.topic.tags.delete(first.tag)
reply.call('This daily topic lost its tag', publication.topic_id, admin)
check(results, 'daily topic without configured tag is ignored') { first.check_ins.where(user_id: admin.id).none? }
DiscourseTagging.tag_topic(publication.topic, Guardian.new(admin), [{ id: first.tag_id }])
# Two distinct activities may safely use the same tag.
shared = make_challenge.call('Shared tag activity', first.tag)
shared_pub = publisher.publish_today(shared)
reply.call('Independent activity check-in', shared_pub.topic_id)
check(results, 'shared tags do not mix activity statistics') { shared.check_ins.where(user_id: user.id).count == 1 && first.check_ins.where(user_id: user.id).count == 1 }
# Calendar boundaries and revisions use activity time, not the user timezone.
travel_to(Time.find_zone!('Beijing').local(today.year, today.month, today.day, 23, 59, 59)) do
  reply.call('Last second of the day', publication.topic_id, admin)
end
check(results, '23:59:59 reply belongs to current activity day') { first.check_ins.where(user_id: admin.id, check_in_date: today).count == 1 }
travel_to(Time.find_zone!('Beijing').local(today.year, today.month, today.day) + 1.day) do
  reply.call('Old topic remains open for discussion', publication.topic_id)
  check(results, 'replying to yesterday does not check in today') { first.check_ins.where(check_in_date: today + 1).none? }
  normal.update_columns(raw: 'Edited yesterday reply #legacy_unused')
  DiscourseDailyChallenge::CheckInService.process_edit(normal)
  check(results, 'editing yesterday does not backdate or add check-in') { first.check_ins.where(user_id: user.id).count == 1 }
  next_pub = publisher.publish_today(first)
  reply.call('New date, normal reply', next_pub.topic_id)
  check(results, 'midnight generates new daily topic and new check-in') { next_pub.topic_id != publication.topic_id && first.check_ins.where(user_id: user.id).count == 2 }
  check(results, 'streak uses activity timezone') { DiscourseDailyChallenge::ChallengeUtils.user_streak(first, user.id) == 2 }
end
# Every publication stays in the activity date range, including the last day.
travel_to(Time.find_zone!('Beijing').local(first.end_date.year, first.end_date.month, first.end_date.day, 12)) do
  check(results, 'last activity day is inclusive') { publisher.publish_today(first).present? }
end
travel_to(Time.find_zone!('Beijing').local(first.end_date.year, first.end_date.month, first.end_date.day, 12) + 1.day) do
  check(results, 'ended activity does not publish another daily topic') { publisher.publish_today(first).nil? }
  badge = Badge.create!(name: "Daily topic test #{suffix}", badge_type_id: BadgeType::Silver, multiple_grant: false)
  first.update!(award_badge: true, badge_name: badge.name, badge_id: badge.id)
  job = Jobs::DailyChallengeFinalPost.new
  job.send(:post_final_results, first)
  final = first.publications.find_by!(kind: 'final')
  check(results, 'final report is separate and marks completion') { final.topic_id != publication.topic_id && first.reload.final_post_sent }
  check(results, 'completion badge awarded from cumulative check-ins') { UserBadge.exists?(user_id: user.id, badge_id: badge.id) }
  job.send(:post_final_results, first)
  check(results, 'final report retry does not duplicate topic or badge') { first.publications.where(kind: 'final').count == 1 && UserBadge.where(user_id: user.id, badge_id: badge.id).count == 1 }
end
future = make_challenge.call('Future activity', first.tag)
future.update!(start_date: today + 1, end_date: today + 3)
check(results, 'future activity does not publish before start') { publisher.publish_today(future).nil? }
# Failure must leave no orphan topic, retain a visible error, then recover.
failed = make_challenge.call('Publication recovery', first.tag)
SiteSetting.daily_challenge_bot_username = 'missing_bot'
begin
  publisher.publish_today(failed)
rescue StandardError
end
check(results, 'invalid bot produces visible failure and no publication') { failed.reload.publication_error.present? && failed.publications.none? }
SiteSetting.daily_challenge_bot_username = bot.username
publisher.publish_today(failed)
check(results, 'retry recovers without duplicate and clears failure') { failed.reload.publication_error.nil? && failed.publications.count == 1 }
# Concurrent workers must converge on the same publication.
concurrent = make_challenge.call('Concurrent workers', first.tag)
ids = 4.times.map do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection { publisher.publish_today(DailyChallenge.find(concurrent.id)).topic_id }
  end
end.map(&:value)
check(results, 'concurrent publishing creates one topic') { ids.uniq.length == 1 && concurrent.publications.count == 1 }
# Reprocess the same visible reply concurrently after removing its existing check-in.
race_post = reply.call('Concurrent check-in event', ids.first)
concurrent.check_ins.delete_all
4.times.map do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection { DiscourseDailyChallenge::CheckInService.process(Post.find(race_post.id)) }
  end
end.each(&:value)
check(results, 'concurrent check-in processing creates one row') { concurrent.check_ins.count == 1 }
# Administrative corrections remain available and are independent of source topic.
manual = DailyCheckIn.create!(challenge_id: concurrent.id, user_id: admin.id, check_in_date: today - 1, admin_added: true)
check(results, 'manual corrections preserve original data model') { manual.admin_added && manual.post_id.nil? }
serialized = DailyChallengeSerializer.new(first, scope: Guardian.new(admin), root: false).as_json
check(results, 'management API exposes activity, tag, history and publication status') { serialized[:name] == first.name && serialized[:daily_topics].length >= 3 && serialized.key?(:publication_error) && serialized[:tag_name] == first.tag.name }
puts "DAILY_TOPICS_RESULT #{ { passed: results.length, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2), activity_id: first.id, today_topic_id: publication.topic_id, bot: bot.username, admin: admin.username }.to_json }"
