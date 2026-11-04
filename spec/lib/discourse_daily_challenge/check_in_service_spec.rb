# frozen_string_literal: true

describe DiscourseDailyChallenge::CheckInService do
  fab!(:user)
  fab!(:category)
  fab!(:home_topic) { Fabricate(:topic, category: category) }
  fab!(:another_topic) { Fabricate(:topic, category: category) }
  fab!(:tag) { Fabricate(:tag, name: "checkin-test") }

  def challenge(scope: "topic", scope_tag: nil)
    DailyChallenge.create!(
      topic_id: home_topic.id,
      hashtag: "nov2026",
      check_in_scope: scope,
      scope_tag: scope_tag,
      start_date: Date.yesterday,
      end_date: Date.tomorrow,
      check_ins_needed: 10,
      challenge_timezone: "UTC",
      check_in_interval: "daily",
      weekly_post_day: 1,
      weekly_post_hour: 9,
      award_badge: false,
    )
  end

  def new_post(topic, raw: "#nov2026 progress")
    Fabricate(:post, topic: topic, user: user, raw: raw)
  end

  before do
    SiteSetting.daily_challenge_enabled = false
    allow(Jobs).to receive(:enqueue)
  end

  it "keeps existing challenges restricted to their linked topic" do
    c = challenge
    outside = new_post(another_topic)
    described_class.process(outside)
    expect(DailyCheckIn.where(challenge_id: c.id)).to be_empty

    inside = new_post(home_topic)
    described_class.process(inside)
    expect(DailyCheckIn.where(challenge_id: c.id).pluck(:post_id)).to eq([inside.id])
  end

  it "counts tagged public topics outside the announcement topic" do
    c = challenge(scope: "topic_tag", scope_tag: tag.name)
    another_topic.tags << tag
    outside = new_post(another_topic)
    described_class.process(outside)
    expect(DailyCheckIn.where(challenge_id: c.id).pluck(:post_id)).to eq([outside.id])
  end

  it "rejects untagged topics in topic-tag mode" do
    c = challenge(scope: "topic_tag", scope_tag: tag.name)
    described_class.process(new_post(another_topic))
    expect(DailyCheckIn.where(challenge_id: c.id)).to be_empty
  end

  it "requires an explicit hashtag for site-wide scope (not an image alone)" do
    c = challenge(scope: "site_hashtag")
    image_post = new_post(another_topic, raw: "Today's drawing")
    allow(image_post).to receive(:uploads).and_return([double(extension: "png")])
    described_class.process(image_post)
    expect(DailyCheckIn.where(challenge_id: c.id)).to be_empty

    outside = new_post(another_topic, raw: "Finished #nov2026 today!")
    described_class.process(outside)
    expect(DailyCheckIn.where(challenge_id: c.id).pluck(:post_id)).to eq([outside.id])
  end

  it "deduplicates check-ins per user and challenge across different topics" do
    c = challenge(scope: "site_hashtag")
    first = new_post(home_topic)
    second = new_post(another_topic)
    described_class.process(first)
    described_class.process(second)
    expect(DailyCheckIn.where(challenge_id: c.id).count).to eq(1)
  end

  it "ignores hidden topics outside the linked topic" do
    c = challenge(scope: "site_hashtag")
    outside = new_post(another_topic)
    another_topic.update!(visible: false)
    described_class.process(outside)
    expect(DailyCheckIn.where(challenge_id: c.id)).to be_empty
  end
end
