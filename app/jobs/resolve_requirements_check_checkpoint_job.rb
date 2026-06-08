class ResolveRequirementsCheckCheckpointJob < ApplicationJob
  queue_as :default

  rescue_from(StandardError) do |exception|
    Rails.logger.error(
      "ResolveRequirementsCheckCheckpointJob failed: #{exception.class}: #{exception.message} " \
      "(job_id=#{job_id}, arguments=#{arguments.inspect})"
    )
    ErrorReporter.capture_exception(
      exception,
      contexts: {
        resolve_requirements_check_checkpoint_job: {
          job_id: job_id,
          arguments: arguments
        }
      }
    )
    raise exception
  end

  # RC treats the checkpoint message as optional (it never blocks submission), so the Slack
  # lookup runs off the request path here — synchronously it was timing out the submit request.
  # Resolves the checkpoint URL, stores it, and posts the checkpoint thread if one is found.
  def perform(review_id:, provided_permalink:, base_url:, project_url:, repo_url:)
    review = RequirementsCheckReview.find_by(id: review_id)
    return unless review
    return if review.checkpoint_message_url.present?
    return unless review.approved? || review.returned? || review.rejected?

    slack_id = review.ship.project.user.slack_id
    url, _failure = SlackCheckpointService.resolve(slack_id, provided_permalink)
    return unless url

    review.update_columns(checkpoint_message_url: url) # best-effort backfill outside the submit request

    PostCheckpointThreadJob.perform_later(
      message_ts: SlackCheckpointService.extract_ts(url),
      ship_id: review.ship_id,
      review_type: "requirements_check",
      review_status: review.status,
      base_url: base_url,
      project_url: project_url,
      repo_url: repo_url
    )
  end
end
