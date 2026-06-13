# frozen_string_literal: true

namespace :review_repo_diff do
  desc "Backfill repo_diff for PENDING reviews created before the feature shipped (the actionable queue)"
  task backfill: :environment do
    enqueue_jobs(scope: ->(klass) { klass.pending.where(repo_diff: nil) })
  end

  desc "Backfill repo_diff for ALL reviews missing it (includes completed/historical)"
  task backfill_all: :environment do
    enqueue_jobs(scope: ->(klass) { klass.where(repo_diff: nil) })
  end

  # The job is cheap for non-re-ships (anchor lookup is DB-only and returns nil
  # before any GitHub call), so we can safely enqueue across the whole scope and
  # let ComputeReviewRepoDiffJob skip the ones with nothing to compare.
  def enqueue_jobs(scope:)
    [ RequirementsCheckReview, DesignReview, BuildReview ].each do |klass|
      reviews = scope.call(klass).joins(ship: :project).where("projects.repo_link LIKE ?", "%github.com%")
      count = reviews.count
      puts "#{klass.name}: #{count} to enqueue"
      reviews.find_each { |review| ComputeReviewRepoDiffJob.perform_later(klass.name, review.id) }
    end
    puts "Done — jobs enqueued on the background queue"
  end
end
