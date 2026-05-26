class RefreshStaleUnifiedThumbnailsJob < ApplicationJob
  queue_as :background

  STALE_AFTER = 24.hours
  PER_RUN_LIMIT = 200
  JITTER_WINDOW = 30.minutes

  def perform
    scope = Project.kept
      .where.not(repo_link: [ nil, "" ])
      .where("unified_thumbnail_checked_at IS NULL OR unified_thumbnail_checked_at < ?", STALE_AFTER.ago)
      .order(Arel.sql("unified_thumbnail_checked_at ASC NULLS FIRST"))
      .limit(PER_RUN_LIMIT)

    enqueued = 0
    scope.find_each do |project|
      jitter = rand(0..JITTER_WINDOW.to_i).seconds
      ComputeProjectUnifiedThumbnailJob.set(wait: jitter).perform_later(project.id)
      enqueued += 1
    end

    Rails.logger.info("RefreshStaleUnifiedThumbnailsJob: enqueued #{enqueued} refreshes")
  end
end
