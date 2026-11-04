# frozen_string_literal: true

class DiscourseDailyChallenge::PublicChallengesController < ApplicationController
  requires_plugin DiscourseDailyChallenge::PLUGIN_NAME
  skip_before_action :check_xhr, only: :index

  def index
    return render "default/empty" if request.format.html?

    activities =
      DailyChallenge
        .where(daily_topics_enabled: true)
        .where(category_id: Category.secured(guardian).select(:id))
        .includes(:tag)
        .order(start_date: :desc)
        .limit(100)
        .sort_by do |challenge|
          challenge.active? ? 0 : (challenge.local_date < challenge.start_date ? 1 : 2)
        end

    render json: { activities: activities.filter_map { |challenge| serialize_activity(challenge) } }
  end

  private

  def serialize_activity(challenge)
    return unless guardian.can_see_tag?(challenge.tag)

    publications =
      challenge.publications.where(kind: "daily").includes(:topic).order(publication_date: :desc)
    topics =
      publications.filter_map do |publication|
        topic = publication.topic
        next unless topic && !topic.trashed? && guardian.can_see_topic?(topic)
        { date: publication.publication_date, title: topic.title, url: topic.relative_url }
      end

    {
      id: challenge.id,
      name: challenge.display_name,
      tag_name: challenge.tag.name,
      topics_url: challenge.topics_url,
      start_date: challenge.start_date,
      end_date: challenge.end_date,
      active: challenge.active?,
      today_topic_url: topics.find { |topic| topic[:date] == challenge.local_date }&.dig(:url),
      daily_topics: topics,
    }
  end
end
