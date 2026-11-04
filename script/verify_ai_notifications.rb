# frozen_string_literal: true
# RAILS_ENV=production bundle exec rails runner plugins/discourse-daily-challenge/script/verify_ai_notifications.rb
abort 'Isolated stage required' unless Discourse.current_hostname.end_with?('.invalid')
SiteSetting.disable_emails='yes'
SiteSetting.default_locale='zh_CN'
I18n.locale=:zh_CN
Jobs.run_later!
checks=[]
verify=lambda do |name,&block|
  raise "FAIL #{name}" unless block.call
  checks << name
  puts "PASS #{name}"
end
agent=DiscourseDailyChallenge::AiNotification.configured_agent
raise 'Configure stage agent first' unless agent
saved_prompt=agent.system_prompt.dup
sender=User.find(agent.user_id)
key=SecureRandom.hex(4)
user=User.create!(username:"notice_user_#{key}",email:"notice.#{key}@example.invalid",active:true,approved:true,trust_level:4)
user.user_option.update!(email_messages_level:0)
today=Time.current.in_time_zone('Beijing').to_date
challenge=DailyChallenge.create!(name:"邮件与私信人设验收 #{key}",category_id:4,tag:Tag.find_by!(name:'中文签到'),hashtag:'unused',daily_topics_enabled:true,start_date:today-5,end_date:today+5,challenge_timezone:'Beijing',check_ins_needed:20,award_badge:false)
pub=DiscourseDailyChallenge::TopicPublisher.publish_today(challenge)
source=PostCreator.create!(user,topic_id:pub.topic_id,raw:'今天读了十二页动画表演分析，整理了角色转身时停顿和动作节奏的笔记。',skip_validations:true)
checkin=challenge.check_ins.find_by!(user_id:user.id)
started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
Jobs::DiscourseDailyChallengeSendCheckinDm.new.execute(user_id:user.id,challenge_id:challenge.id,check_in_id:checkin.id)
elapsed=(Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(2)
stored=PluginStore.get(DiscourseDailyChallenge::AiNotification::STORE,"checkin:#{checkin.id}")
raise "AI generation failed: #{stored.inspect}" unless stored && stored['generated']
post=Post.find(stored.fetch('post_id'))
verify.call('success private message is authored by configured AI bot') { post.user_id==sender.id }
verify.call('success message uses actual generated persona line') { post.raw.start_with?('>>') && post.raw.lines.first.include?('❤') }
verify.call('verified check-in date, count and source link remain authoritative') { post.raw.include?(today.iso8601) && post.raw.include?('1 / 20') && post.raw.include?(source.url) }
verify.call('recipient alone is the invited human') { post.topic.allowed_users.where('users.id > 0').pluck(:id)==[user.id] }
count=Post.count
Jobs::DiscourseDailyChallengeSendCheckinDm.new.execute(user_id:user.id,challenge_id:challenge.id,check_in_id:checkin.id)
verify.call('retry does not regenerate or duplicate successful notification') { Post.count==count && PluginStore.get(DiscourseDailyChallenge::AiNotification::STORE,"checkin:#{checkin.id}")['post_id']==post.id }
mail=UserNotifications.user_private_message(user,post:post,notification_data_hash:{original_username:sender.username,original_user_id:sender.id,topic_title:post.topic.title}).message
text=mail.text_part&.decoded.to_s
html=mail.html_part&.decoded.to_s
verify.call('standard notification email includes generated persona content') { (text+html).include?(post.raw.lines.first.strip.sub(/^>>\s*/,'')) || text.include?('❤') && html.include?('❤') }
verify.call('standard notification email identifies AI bot as sender') { mail.to_s.include?(sender.username) || mail.from.first.include?('noreply') && html.include?('监督官') }
verify.call('user email preference is not changed') { user.user_option.reload.email_messages_level==0 }
verify.call('saved persona instructions are not modified') { agent.reload.system_prompt==saved_prompt }
# Actual model invocation for the missed-check-in scenario.
missing=User.create!(username:"dc_miss_#{key}",email:"missing.#{key}@example.invalid",active:true,approved:true,trust_level:4)
DailyCheckIn.create!(challenge_id:challenge.id,user_id:missing.id,check_in_date:today-3,admin_added:true)
reminder=Jobs::DiscourseDailyChallengeSendReminders.new.send(:send_reminder_dm,DiscourseDailyChallenge.bot_user,challenge,missing.id,:first)
verify.call('reminder uses same AI bot and links today topic') { reminder.user_id==sender.id && reminder.raw.include?(pub.topic.url) }
reminder_key="reminder:#{challenge.id}:#{missing.id}:first:#{today-3}"
verify.call('reminder persona is actually generated') { PluginStore.get(DiscourseDailyChallenge::AiNotification::STORE,reminder_key)['generated'] }
verify.call('already signed-in participant is not reminded') { Jobs::DiscourseDailyChallengeSendReminders.new.send(:send_reminder_dm,DiscourseDailyChallenge.bot_user,challenge,user.id,:first).nil? }
# Reminder generation runs in individual retryable jobs, outside the daily scan.
reminder_job=Jobs::DiscourseDailyChallengeSendReminderDm.new
reminder_delivery_key="daily_challenge:reminder_1:#{challenge.id}:#{missing.id}"
Discourse.redis.del(reminder_delivery_key)
posts_before=Post.count
calls_before=AiApiAuditLog.where(feature_name:'daily_challenge_notification').count
2.times { reminder_job.execute(challenge_id:challenge.id,user_id:missing.id,stage:'first') }
verify.call('asynchronous reminder retries reuse PM without another model call') { Post.count==posts_before && AiApiAuditLog.where(feature_name:'daily_challenge_notification').count==calls_before && Discourse.redis.exists?(reminder_delivery_key) }
DailyCheckIn.create!(challenge_id:challenge.id,user_id:missing.id,check_in_date:today,admin_added:true)
Discourse.redis.del(reminder_delivery_key)
reminder_job.execute(challenge_id:challenge.id,user_id:missing.id,stage:'first')
verify.call('delayed reminder worker cancels after a successful check-in') { Post.count==posts_before && !Discourse.redis.exists?(reminder_delivery_key) }
# Exercise failure and concurrent retries without more model calls.
service=DiscourseDailyChallenge::AiNotification
original=service.method(:generate)
service.define_singleton_method(:generate) { |*| raise Timeout::Error }
fallback=service.deliver(event_key:"test-failure:#{key}",kind: :checkin,challenge:challenge,user:user,check_in:checkin,fallback_sender:DiscourseDailyChallenge.bot_user,title:'Fallback check-in',fallback_raw:'Fixed fallback')
verify.call('model timeout falls back to persona bot plus verified statistics') { fallback.user_id==sender.id && fallback.raw.include?('签到成功') && fallback.raw.include?('1 / 20') }
verify.call('generation failure is recorded for diagnosis') { PluginStore.get(service::STORE,"test-failure:#{key}")['error']=='Timeout::Error' }
calls=0
mutex=Mutex.new
service.define_singleton_method(:generate) { |*| mutex.synchronize { calls+=1 }; sleep 0.2; '>> [并发验收]❤ 哼，今天也有好好出现嘛，本小姐先记下你的小小努力，明天可别溜走呀，杂鱼❤' }
ids=3.times.map do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      service.deliver(event_key:"test-concurrent:#{key}",kind: :checkin,challenge:DailyChallenge.find(challenge.id),user:User.find(user.id),check_in:DailyCheckIn.find(checkin.id),fallback_sender:DiscourseDailyChallenge.bot_user,title:'Concurrent check-in',fallback_raw:'Fixed fallback').id
    end
  end
end.map(&:value)
verify.call('concurrent retries create one PM and one model invocation') { ids.uniq.length==1 && calls==1 }
service.define_singleton_method(:generate,original)
# Disabled AI leaves the pre-existing fixed text and sender intact.
SiteSetting.daily_challenge_notification_ai_agent_id=0
fixed=service.deliver(event_key:"test-disabled:#{key}",kind: :checkin,challenge:challenge,user:user,check_in:checkin,fallback_sender:DiscourseDailyChallenge.bot_user,title:'Legacy',fallback_raw:'Fixed original text')
verify.call('disabling AI preserves fixed template and original sender') { fixed.raw=='Fixed original text' && fixed.user_id==DiscourseDailyChallenge.bot_user.id }
SiteSetting.daily_challenge_notification_ai_agent_id=agent.id
puts "AI_NOTIFICATION_RESULT #{ {passed:checks.length,success_seconds:elapsed,success_post_id:post.id,reminder_post_id:reminder.id,persona_line:post.raw.lines.first.strip}.to_json }"
