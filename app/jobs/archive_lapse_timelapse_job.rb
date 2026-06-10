class ArchiveLapseTimelapseJob < ApplicationJob
  queue_as :heavy # video download + hashing, like TimelapseActivityCheckJob

  def perform(lapse_timelapse_id, force: false)
    lapse_timelapse = LapseTimelapse.find_by(id: lapse_timelapse_id)
    return unless lapse_timelapse # row deleted before the job ran

    LapseArchiveService.new.archive!(lapse_timelapse, force: force)
  end
end
