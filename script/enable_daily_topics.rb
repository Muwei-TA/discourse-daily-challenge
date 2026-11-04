# frozen_string_literal: true
# Run after backup and schema migration. Existing check-in rows are never rewritten.
# RAILS_ENV=production bundle exec rails runner plugins/discourse-daily-challenge/script/enable_daily_topics.rb
bot = DiscourseDailyChallenge.bot_user
abort 'Configure an active challenge bot before migrating activities' unless bot&.active? && bot.approved? && !bot.suspended?
DailyChallenge.active.where(daily_topics_enabled: false).find_each do |challenge|
  next unless challenge.active?
  old_topic = challenge.topic
  raise "Activity #{challenge.id} has no original topic" unless old_topic
  before = challenge.check_ins.order(:id).pluck(:id, :user_id, :check_in_date, :post_id, :admin_added)
  publication = nil
  challenge.with_lock do
    tag = old_topic.tags.first || DiscourseDailyChallenge::TagManager.resolve!(challenge.hashtag, Guardian.new(bot))
    challenge.update!(name: old_topic.title, category_id: old_topic.category_id, tag: tag,
                      daily_topics_enabled: true, check_in_interval: 'daily')
    publication = DiscourseDailyChallenge::TopicPublisher.publish_today(challenge)
    raise 'Daily publication missing' unless publication
    PostCreator.create!(bot, topic_id: old_topic.id, skip_validations: true, raw:
      "本活动已切换为每天一个打卡贴，历史签到记录全部保留。\n\n" \
      "从现在起，请在[今日打卡贴](#{publication.topic.url})回复签到，每人每天一次，无须填写 #标签或上传图片。" \
      "本月度话题保留供讨论，后续回复不再计入签到；跨天回复旧打卡贴也不计签到。\n\n" \
      "[浏览活动话题及每日打卡贴](#{challenge.topics_url})")
    after = challenge.check_ins.order(:id).pluck(:id, :user_id, :check_in_date, :post_id, :admin_added)
    raise 'Historical check-in data changed during migration' unless before == after
  end
  puts({ activity_id: challenge.id, old_topic_id: old_topic.id, today_topic_id: publication.topic_id,
         preserved_check_ins: before.length, tag_id: challenge.tag_id, name: challenge.name }.to_json)
end
