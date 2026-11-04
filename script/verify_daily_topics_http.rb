# frozen_string_literal: true
# Additional real Rails request, permission, notification and migration checks.
abort 'Isolated stage required' unless Discourse.current_hostname.end_with?('.invalid')
SiteSetting.disable_emails = 'yes'
SiteSetting.login_required = false
SiteSetting.force_https = false
SiteSetting.must_approve_users = false
SiteSetting.default_locale = 'zh_CN'
I18n.locale = :zh_CN
Jobs.run_later!
results = []
check = lambda do |name, &block|
  raise "FAIL #{name}" unless block.call
  results << name
  puts "PASS #{name}"
end
suffix = SecureRandom.hex(4)
passwords = {}
make_user = lambda do |label, **attributes|
  password = SecureRandom.hex(24)
  user = User.create!({username: "http_#{label}_#{suffix}", email: "http.#{label}.#{suffix}@example.invalid",
                      password: password, active: true, approved: true, trust_level: 4}.merge(attributes))
  user.activate
  passwords[user.id] = password
  user
end
admin = make_user.call('admin', admin: true)
member = make_user.call('member')
bot = DiscourseDailyChallenge.bot_user
raise 'Stage bot missing' unless bot
login = lambda do |user|
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! Discourse.current_hostname
  session.get('/session/csrf.json')
  csrf = session.response.parsed_body.fetch('csrf')
  headers = {'X-CSRF-Token'=>csrf, 'X-Requested-With'=>'XMLHttpRequest'}
  session.post('/session.json', params: {login: user.username, password: passwords.fetch(user.id)}, headers: headers)
  raise 'Test login failed' unless session.response.status == 200 && !session.response.parsed_body['error']
  [session, headers]
end
session, headers = login.call(admin)
base = '/admin/plugins/discourse-daily-challenge'
session.get("#{base}/configuration.json", headers: headers)
check.call('admin configuration endpoint lists categories and exact emoji tags') { session.response.status == 200 && session.response.parsed_body['tags'].include?('👩‍💻') }
today = Time.current.in_time_zone('Beijing').to_date
params = {name: "HTTP 活动 #{suffix}", category_id: 4, tag_name: 'API阅读📚', start_date: today,
          end_date: today+3, challenge_timezone: 'Beijing', check_ins_needed: 2, award_badge: false}
session.post("#{base}/challenges.json", params: params, headers: headers)
check.call('admin creates activity without fixed topic ID') { session.response.status == 200 && session.response.parsed_body.dig('challenge','topic_id').nil? }
check.call('save response immediately contains today topic link') { session.response.parsed_body.dig('challenge','today_topic_url').present? }
challenge = DailyChallenge.find(session.response.parsed_body.fetch('challenge').fetch('id'))
publication = DiscourseDailyChallenge::TopicPublisher.publish_today(challenge)
check.call('configured tag survives actual publication') { publication.topic.tags.exists?(id: challenge.tag_id) && challenge.tag.name == 'api阅读📚' }
session.put("#{base}/challenges/#{challenge.id}.json", params: {name: "Updated HTTP 活动 #{suffix}",tag_name: challenge.tag.name}, headers: headers)
check.call('admin updates independent activity configuration') { session.response.status == 200 && challenge.reload.name.start_with?('Updated') }
session.get("#{challenge.tag.url}.json", headers: headers)
check.call('native ID-based emoji tag page lists the daily topic') { session.response.status == 200 && session.response.parsed_body.dig('topic_list','topics').any? { |t| t['id'] == publication.topic_id } }
session.put("#{base}/challenges/#{challenge.id}.json", params: {tag_name: '更新标签📚'}, headers: headers)
check.call('changing activity tag updates current daily topic atomically') { session.response.status == 200 && publication.topic.reload.tags.exists?(id: challenge.reload.tag_id) && challenge.tag.name == '更新标签📚' }
session.post("#{base}/challenges.json", params: params.merge(tag_name: 'bad#tag'), headers: headers)
check.call('unsafe topic tag rejected') { session.response.status.between?(400,499) }
session.post("#{base}/challenges.json", params: params.merge(category_id: -999), headers: headers)
check.call('unknown category rejected') { session.response.status.between?(400,499) }
# Normal Discourse post endpoint and edit hook: content does not control eligibility.
session_member, member_headers = login.call(member)
['纯文字回复，今天的阅读已经完成并且整理好了笔记。', '#old_trigger tagged reply', '![image](https://example.invalid/photo.png)'].each do |raw|
  challenge.check_ins.where(user_id: member.id).delete_all
  sleep(SiteSetting.rate_limit_create_post + 0.1)
  session_member.post('/posts.json', params: {topic_id: publication.topic_id,raw: raw}, headers: member_headers)
  raise "Post request failed: #{session_member.response.status} #{session_member.response.parsed_body.inspect}" unless session_member.response.status == 200
  check.call("post endpoint counts #{raw.start_with?('!') ? 'image only' : raw.start_with?('#') ? 'tagged reply' : 'ordinary reply'}") { session_member.response.status == 200 && challenge.check_ins.where(user_id: member.id).count == 1 }
end
session_member.get("#{base}/configuration.json", headers: member_headers)
check.call('ordinary member cannot enter admin management') { session_member.response.status.between?(400,499) }
session_member.get('/challenges/configuration.json', headers: member_headers)
check.call('ordinary member cannot use category-manager API') { session_member.response.status.between?(400,499) }
# Category moderators keep their scoped management route and cannot cross categories.
group = Group.create!(name: "dcmods_#{suffix}")
group.add(member)
CategoryModerationGroup.create!(category_id: 4, group_id: group.id)
session_member.get('/challenges/configuration.json', headers: member_headers)
check.call('category moderator sees only assigned category options') { session_member.response.status == 200 && session_member.response.parsed_body['categories'].map { |c| c['id'] } == [4] }
session_member.post('/challenges/challenges.json', params: params.merge(name: "Category manager #{suffix}"), headers: member_headers)
check.call('category moderator can create activity in assigned category') { session_member.response.status == 200 }
session_member.post('/challenges/challenges.json', params: params.merge(category_id: 2), headers: member_headers)
check.call('category moderator cannot create activity in other category') { session_member.response.status.between?(400,499) }
# Supplement and remove a check-in through the preserved administrative endpoints.
session.post("#{base}/challenges/#{challenge.id}/check_ins.json", params: {user_id: member.id,check_in_date: today-1}, headers: headers)
check.call('manual check-in API remains functional') { session.response.status == 200 && challenge.check_ins.exists?(user_id: member.id,check_in_date: today-1,admin_added:true) }
manual = challenge.check_ins.find_by!(user_id: member.id,check_in_date: today-1)
session.delete("#{base}/challenges/#{challenge.id}/check_ins/#{manual.id}.json", headers: headers)
check.call('manual check-in removal API remains functional') { session.response.status == 200 && !DailyCheckIn.exists?(manual.id) }
session.get("#{base}/challenges/#{challenge.id}/drawing.json", params: {min_checkins:1}, headers: headers)
check.call('prize drawing uses cumulative check-ins') { session.response.status == 200 && session.response.parsed_body['usernames'].include?(member.username) }
session.post("#{base}/challenges/#{challenge.id}/post_leaderboard.json", headers: headers)
check.call('manual leaderboard endpoint publishes separate report') { session.response.status == 200 && challenge.publications.exists?(kind:'weekly') }
Jobs::DiscourseDailyChallengeSendCheckinDm.new.execute(user_id:member.id, challenge_id:challenge.id)
pm = Post.joins(:topic).where(user_id: bot.id, topics:{archetype:Archetype.private_message}).order(id: :desc).first
check.call('confirmation DM uses activity identity and current daily topic') { pm.raw.include?(challenge.name) && pm.raw.include?("/#{publication.topic_id}") }
check.call('onboarding describes reply-based signup instead of hashtag requirement') { pm.raw.include?('当日打卡贴回复即可签到') }
Jobs::DiscourseDailyChallengeSendCompletionDm.new.execute(user_id:member.id, challenge_id:challenge.id)
pm = Post.joins(:topic).where(user_id: bot.id, topics:{archetype:Archetype.private_message}).order(id: :desc).first
check.call('completion DM links the current daily topic') { pm.raw.include?("/#{publication.topic_id}") }
commands_before = Topic.where(archetype:Archetype.private_message).count
PostCreator.create!(member, topic_id:publication.topic_id, raw:"@#{bot.username} progress", skip_validations:true)
check.call('mention commands resolve challenge from daily publication') { Topic.where(archetype:Archetype.private_message).count > commands_before }
Jobs::DiscourseDailyChallengeSendReminders.new.send(:send_reminder_dm, bot, challenge, member.id, :first)
pm = Post.joins(:topic).where(user_id: bot.id, topics:{archetype:Archetype.private_message}).order(id: :desc).first
check.call('reminder DM links current activity topic') { pm.raw.include?(challenge.name) && pm.raw.include?("/#{publication.topic_id}") }
# Restricted category publication must fail before creating any topic.
private_category = Category.create!(name: "Private activity #{suffix}",color:'0088CC',user:admin)
private_category.set_permissions(staff: 1)
private_category.save!
private_activity = DailyChallenge.create!(name:"Private #{suffix}",category:private_category,tag:challenge.tag,
  daily_topics_enabled:true,hashtag:'unused',start_date:today,end_date:today+2,check_ins_needed:2,challenge_timezone:'Beijing',award_badge:false)
begin
  DiscourseDailyChallenge::TopicPublisher.publish_today(private_activity)
rescue StandardError
end
check.call('bot denied category creates no topic and reports failure') { private_activity.reload.publication_error.present? && private_activity.publications.none? }
anon = ActionDispatch::Integration::Session.new(Rails.application)
anon.host! Discourse.current_hostname
anon.get('/daily-challenges.json')
check.call('public activity page does not reveal restricted categories') { anon.response.status == 200 && !anon.response.parsed_body['activities'].any? { |a| a['id'] == private_activity.id } }
# Migrate an old topic while preserving rows and refusing duplicate same-day signup.
old = PostCreator.create!(admin,title:"Legacy migration #{suffix}",raw:'Original monthly activity',category:4,tags:[challenge.tag.name],skip_validations:true)
legacy = DailyChallenge.create!(topic_id:old.topic_id,hashtag:'old',start_date:today-1,end_date:today+3,
  check_ins_needed:2,challenge_timezone:'Beijing',category_id:4,award_badge:false)
history = DailyCheckIn.create!(challenge_id:legacy.id,user_id:member.id,check_in_date:today,post_id:old.id)
load Rails.root.join('plugins/discourse-daily-challenge/script/enable_daily_topics.rb')
legacy.reload
check.call('legacy activity migration preserves source record exactly') { legacy.daily_topics_enabled? && history.reload.attributes.slice('user_id','check_in_date','post_id') == {'user_id'=>member.id,'check_in_date'=>today,'post_id'=>old.id} }
new_topic = legacy.today_topic
PostCreator.create!(member,topic_id:new_topic.id,raw:'Already checked in earlier today',skip_validations:true)
check.call('migration does not double-count already signed-in users') { legacy.check_ins.where(user_id:member.id).count == 1 }
PostCreator.create!(admin,topic_id:old.topic_id,raw:'#old Original monthly topic no longer accepts signup',skip_validations:true)
check.call('old monthly topic stops counting after cutover') { legacy.check_ins.where(user_id:admin.id).none? }
before = Post.where(topic_id:old.topic_id).count
load Rails.root.join('plugins/discourse-daily-challenge/script/enable_daily_topics.rb')
check.call('migration script is idempotent') { Post.where(topic_id:old.topic_id).count == before && legacy.publications.where(kind:'daily').count == 1 }
puts "HTTP_TOPICS_RESULT #{ {passed:results.length,activity_id:challenge.id,legacy_id:legacy.id}.to_json }"
