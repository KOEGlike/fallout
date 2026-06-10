class AddArchiveFieldsToLapseTimelapses < ActiveRecord::Migration[8.1]
  def change
    add_column :lapse_timelapses, :archived_at, :datetime, if_not_exists: true
    add_column :lapse_timelapses, :archive_video_byte_size, :bigint, if_not_exists: true
    add_column :lapse_timelapses, :archive_checksum, :string, if_not_exists: true # sha256 of archived video
  end
end
