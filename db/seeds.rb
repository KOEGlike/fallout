# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Shop items
shop_items = [
  {
    name: "Fallout Sticker Pack",
    description: "A set of 5 die-cut Fallout stickers.",
    price: 10,
    currency: "koi",
    image_url: "https://assets.hackclub.com/stickers/blobfish.svg",
    status: "available",
    featured: false,
    ticket: false,
    requires_shipping: true,
    grants_streak_freeze: false
  },
  {
    name: "Streak Freeze",
    description: "Protect your streak for one day.",
    price: 20,
    currency: "koi",
    image_url: "https://assets.hackclub.com/icon-rounded.png",
    status: "available",
    featured: false,
    ticket: false,
    requires_shipping: false,
    grants_streak_freeze: true
  },
  {
    name: "Ticket to Fallout",
    description: "Your invitation to the in-person Fallout event.",
    price: 1,
    currency: "koi",
    image_url: "https://user-cdn.hackclub-assets.com/019d5ed7-69be-7db6-88f9-2062a45e4df1/ticket.webp",
    status: "available",
    featured: true,
    ticket: true,
    requires_shipping: false,
    grants_streak_freeze: false
  }
]

shop_items.each do |attrs|
  ShopItem.find_or_create_by!(name: attrs[:name]) do |item|
    item.assign_attributes(attrs)
  end
end

puts "Seeded #{ShopItem.count} shop items"

# Dev-only data: clean up junk test rows, then seed curated demo data
if Rails.env.development?
  # Purge legacy test-fixture rows from minitest jobs/models that bypass transactional fixtures
  # (test/models/project_test.rb, test/jobs/compute_project_unified_thumbnail_job_test.rb).
  # Identified by the exact display names the tests hardcode — narrow enough that real users
  # (HCA-authenticated, type=nil) can never match. destroy_all cascades through dependent: :destroy
  # on projects, journal entries, ships, koi_transactions, etc.
  fixture_users = User.where(type: "TrialUser", display_name: [ "Unified Tester", "Project Tester" ])
  purged_count = fixture_users.count
  if purged_count.positive?
    # FeaturedProject's FK to projects is non-cascading by design (we want hard project deletes
    # to be explicit). Clear referencing rows first so the user → project cascade can proceed.
    FeaturedProject.where(project_id: Project.where(user_id: fixture_users.select(:id))).delete_all
    fixture_users.destroy_all
    puts "Purged #{purged_count} legacy test-fixture users (cascaded to their projects)"
  end

  # --- Demo dataset --------------------------------------------------------
  # Heal legacy broken avatars left behind by system specs, then create a
  # curated set of full users + diverse projects + journal entries so the
  # bulletin board / explore feed / admin dashboards have realistic content.
  # Idempotent: re-running only fills gaps. Pictures come from picsum.photos
  # (deterministic seed → stable image across runs).
  require "open-uri"

  PICSUM_AVATAR = ->(seed) { "https://picsum.photos/seed/fallout-user-#{seed}/200/200" }
  PICSUM_THUMB  = ->(seed) { "https://picsum.photos/seed/fallout-proj-#{seed}/800/1000" }
  PICSUM_JOURNAL = ->(seed) { "https://picsum.photos/seed/fallout-journal-#{seed}/900/600" }

  # 1. Fix obviously-broken avatars on existing test/trial users so the UI
  #    stops rendering broken-image icons. update_column skips validations and
  #    callbacks — these are display-only fixes.
  broken_avatar_users = User.where(avatar: [ "https://example.com/a.png", nil, "" ])
  broken_count = broken_avatar_users.count
  broken_avatar_users.find_each do |u|
    u.update_column(:avatar, PICSUM_AVATAR.call(u.id))
  end
  puts "Healed #{broken_count} broken user avatars" if broken_count.positive?

  # 2. Curated demo users — full (non-trial) so they show on the explore feed
  #    and can own featured projects without the trial-account guards.
  demo_people = [
    { display: "Alex Tran",     first: "Alex",   last: "Tran" },
    { display: "Tongyu Zhou",   first: "Tongyu", last: "Zhou" },
    { display: "Cyao Lin",      first: "Cyao",   last: "Lin" },
    { display: "Antush Patel",  first: "Antush", last: "Patel" },
    { display: "Mira Suzuki",   first: "Mira",   last: "Suzuki" },
    { display: "Joon Park",     first: "Joon",   last: "Park" },
    { display: "Sade Okafor",   first: "Sade",   last: "Okafor" },
    { display: "Felix Romero",  first: "Felix",  last: "Romero" }
  ]

  demo_projects = [
    { name: "Biblically Accurate Keyboard",
      description: "A 36-key split keyboard inspired by the wild geometry of biblical seraphim. ZMK firmware, hand-wired matrix, 3D-printed case.",
      repo_link: "https://github.com/fallout-demo/biblical-keyboard",
      tags: %w[hardware keyboard 3d-printing] },
    { name: "Mini Maimai",
      description: "Pocket-sized rhythm cabinet that emulates Sega's maimai. 8 capacitive touch buttons, OLED display, USB-C charging.",
      repo_link: "https://github.com/fallout-demo/mini-maimai",
      tags: %w[hardware arcade rhythm-game] },
    { name: "Icepi Zero",
      description: "Raspberry Pi Zero stuffed inside a translucent Game Boy Pocket shell. Runs RetroArch and a custom launcher in Pygame.",
      repo_link: "https://github.com/fallout-demo/icepi-zero",
      tags: %w[hardware emulation handheld] },
    { name: "Split Wave",
      description: "Open-source ergonomic split keyboard with a tented case and per-key RGB underglow. KiCad designs included.",
      repo_link: "https://github.com/fallout-demo/split-wave",
      tags: %w[keyboard ergonomics kicad] },
    { name: "RainPi Weather Station",
      description: "ESP32-driven weather rig with BME280 + tipping bucket rain gauge, piping live data into a self-hosted Grafana board.",
      repo_link: "https://github.com/fallout-demo/rainpi",
      tags: %w[iot esp32 grafana] },
    { name: "Glow Pen",
      description: "Smart-pen prototype with a capacitive ink sensor and an addressable LED ferrule. Pairs over BLE to a sketch app.",
      repo_link: "https://github.com/fallout-demo/glow-pen",
      tags: %w[hardware ble wearable] },
    { name: "Loopback Drum Pad",
      description: "Hand-machined aluminum drum pads driving a CME-pitched groovebox over MIDI. Built around a Teensy 4.1.",
      repo_link: "https://github.com/fallout-demo/loopback-pad",
      tags: %w[music midi teensy] },
    { name: "Tiny Telescope",
      description: "DIY equatorial tracking mount with a stepper-driven RA axis. STM32 controller, hand-cut aluminum, 3D-printed gears.",
      repo_link: "https://github.com/fallout-demo/tiny-telescope",
      tags: %w[astronomy hardware stm32] }
  ]

  journal_templates = [
    "Kicked off the project today — sketched the rough enclosure on paper and ordered the first batch of parts.",
    "Got the bare-bones firmware compiling. Pushed an initial commit; mostly just I/O setup and a debug LED blink.",
    "Spent the afternoon on the wiring harness. Rerouted everything under the main PCB so the lid finally closes.",
    "Friday demo went well — useful feedback from the cohort. Going to refactor the input handling before the next iteration.",
    "Soldering session #3. Burns: 0. Solder joints: 84. Probably the best ratio yet.",
    "Took the prototype to a coffee shop and let people try it. Big win on the haptics — biggest complaint is the screen brightness.",
    "Long debugging session. Turns out the bus was floating because I forgot a pull-up. Adding it to the BOM so future-me doesn't forget."
  ]

  demo_emails = demo_people.map { |p| "#{p[:display].parameterize}@fallout.demo" }

  demo_people.zip(demo_projects).each_with_index do |(person, proj), index|
    next unless person && proj

    slug = person[:display].parameterize
    email = "#{slug}@fallout.demo"

    # Curated full users (type=nil). slack_id/hca_id are required for non-trial accounts.
    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.assign_attributes(
        type: nil,
        display_name: person[:display],
        first_name: person[:first],
        last_name: person[:last],
        avatar: PICSUM_AVATAR.call(slug),
        timezone: "America/New_York",
        slack_id: "UDEMO#{(1000 + index)}",
        hca_id: "demo-hca-#{slug}",
        onboarded: true,
        is_adult: true,
        roles: %w[user]
      )
      user.save!
    elsif user.avatar.blank? || user.avatar.include?("example.com")
      user.update!(avatar: PICSUM_AVATAR.call(slug))
    end

    project = Project.find_or_initialize_by(name: proj[:name], user: user)
    if project.new_record?
      project.assign_attributes(
        description: proj[:description],
        repo_link: proj[:repo_link],
        tags: proj[:tags],
        is_unlisted: false
      )
      project.save!
    end

    # Attach a deterministic picsum cover so the bulletin board featured grid
    # and explore feed have real images instead of empty placeholders.
    unless project.unified_thumbnail.attached?
      url = PICSUM_THUMB.call(proj[:name].parameterize)
      begin
        downloaded = URI.parse(url).open(read_timeout: 10)
        project.unified_thumbnail.attach(
          io: downloaded,
          filename: "#{proj[:name].parameterize}.jpg",
          content_type: "image/jpeg"
        )
      rescue => e
        warn "  could not attach thumbnail for #{project.name}: #{e.class}: #{e.message}"
      end
    end

    # Three journal entries per project, each with one picsum image attached so
    # the explore feed cards have inline media variety.
    needed = 3 - project.journal_entries.count
    needed.times do |n|
      entry = JournalEntry.create!(
        user: user,
        project: project,
        content: journal_templates[(index + n) % journal_templates.length]
      )

      begin
        downloaded = URI.parse(PICSUM_JOURNAL.call("#{slug}-#{project.id}-#{n}")).open(read_timeout: 10)
        entry.images.attach(
          io: downloaded,
          filename: "journal-#{entry.id}.jpg",
          content_type: "image/jpeg"
        )
      rescue => e
        warn "  could not attach journal image for entry ##{entry.id}: #{e.class}: #{e.message}"
      end
    end
  end

  demo_user_scope = User.verified.where(email: demo_emails)
  puts "Demo users: #{demo_user_scope.count}"
  puts "Demo projects: #{Project.where(user_id: demo_user_scope.select(:id)).count}"
  puts "Demo journal entries: #{JournalEntry.where(user_id: demo_user_scope.select(:id)).count}"

  # Give the first demo user a separate project with 50 approved hours so the path/hours-stats
  # flows have data to render. Previously this targeted a TrialUser by id, but that user is
  # purged above — anchor it to a curated demo identity instead.
  hours_target = demo_user_scope.order(:id).first
  if hours_target
    hours = 50
    seconds = hours * 3600

    hours_project = Project.find_or_create_by!(name: "Seeded Hours Project", user: hours_target) do |p|
      p.description = "Seeded project for testing approved hours"
      p.manual_seconds = seconds
    end
    hours_project.update!(manual_seconds: seconds)

    hours_ship = Ship.find_or_create_by!(project: hours_project) do |s|
      s.ship_type = :design
      s.status = :approved
      s.approved_public_seconds = seconds
      s.justification = "Seeded for testing"
    end
    hours_ship.update!(status: :approved, approved_public_seconds: seconds)

    puts "Gave #{hours_target.display_name} (##{hours_target.id}) #{hours} approved hours via project ##{hours_project.id}"
  end
end
