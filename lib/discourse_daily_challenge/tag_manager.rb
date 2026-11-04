# frozen_string_literal: true

module DiscourseDailyChallenge
  module TagManager
    # Existing tags are assigned by ID; new labels intentionally avoid clean_tag,
    # which strips emoji. Category/tag permissions still run through tag_topic.
    def self.resolve!(name, guardian)
      name = name.to_s.unicode_normalize(:nfc).strip
      name = name.downcase if SiteSetting.force_lowercase_tags
      if name.blank? || name.length > SiteSetting.max_tag_length ||
           name.match?(/[\s\p{Cc}\p{Cs}]/) || name.match?(DiscourseTagging::TAGS_FILTER_REGEXP)
        raise Discourse::InvalidParameters.new(:tag_name)
      end
      existing = Tag.where_name(name).first
      if existing
        raise Discourse::InvalidAccess unless Tag.visible(guardian).exists?(id: existing.id)
        return existing
      end
      raise Discourse::InvalidAccess unless guardian.can_create_tag?
      Tag.create!(name: name)
    rescue ActiveRecord::RecordNotUnique
      Tag.where_name(name).first!
    end

    def self.validate_category!(tag, category, guardian)
      probe = Topic.new(category: category)
      unless DiscourseTagging.validate_category_tags(guardian, probe, category, [tag.name])
        raise Discourse::InvalidParameters.new(:tag_name)
      end
      restricted = (DiscourseTagging.readonly_tag_names(guardian) + DiscourseTagging.hidden_tag_names(guardian)) - DiscourseTagging.permitted_tag_names(guardian)
      raise Discourse::InvalidAccess unless guardian.can_tag_topics? && !restricted.include?(tag.name)
      allowed = DiscourseTagging.filter_allowed_tags(guardian, for_topic: true, category: category,
                                                     only_tag_names: [tag.name], selected_tags: [tag.name])
      raise Discourse::InvalidAccess unless allowed.any? { |candidate| candidate.id == tag.id }
    end
  end
end
