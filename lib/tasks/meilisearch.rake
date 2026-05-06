namespace :meilisearch do
  desc "Reindex all searchable models into Meilisearch (Project + JournalEntry)"
  task reindex: :environment do
    [ Project, JournalEntry ].each_with_index do |model, i|
      sleep 5 if i.positive? # let Meilisearch settle between models to avoid memory spikes overlapping
      puts "Reindexing #{model.name} (#{model.count} records)…"
      model.ms_reindex!
      puts "  done."
    end
  end
end
