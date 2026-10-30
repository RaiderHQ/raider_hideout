# Derives a unique, route-safe slug from +name+ on create.
module Sluggable
  extend ActiveSupport::Concern

  RESERVED_SLUGS = %w[new edit].freeze

  included do
    validates :slug, presence: true, uniqueness: true, exclusion: { in: RESERVED_SLUGS }
    before_validation :assign_slug, on: :create
  end

  def to_param
    slug
  end

  private

  def assign_slug
    return if name.blank?

    base = name.parameterize.presence || model_name.singular
    candidate = base
    suffix = 1
    while RESERVED_SLUGS.include?(candidate) || self.class.exists?(slug: candidate)
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end
    self.slug = candidate
  end
end
