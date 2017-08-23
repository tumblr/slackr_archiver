#!/usr/bin/env ruby

require 'slack-ruby-client'
require 'date'
require 'csv'
require 'logger'
require 'highline/import'

# logging options
archiver_log = Logger.new("slackr_archiver.log", 6, 50240000)
archiver_log.datetime_format = '%Y-%m-%d %H:%M:%S'
archiver_log.formatter = proc do |severity, datetime, progname, msg|
   "#{datetime} -- :  #{msg}\n"
end

# local variables
# set days inactive here
days_inactive_threshold = 60
notify_days_inactive_threshold = 30
# don't modify these
channels_to_archive = []
active_channels = []
notify_channels = []
channels_to_archive = []
run_date = Time.now

# command line arguments info
if ["--help", "-h", "?", nil].include? ARGV[0]
  STDERR.puts("Missing Flag.\n\n")
  puts "The Slackr Archiver\n"
  puts "v1, 2017\n\n"
  puts "Usage:  archiver_slackr <flag>"
  puts "    -d, --dry-run                 runs in DRY-RUN mode (do this first! no channels will be archived)"
  puts "    -n, --notify                  runs in NOTIFY mode. (sends a polite message to any channels that are 30 days inactive (but less than 60)"
  puts "    -a, --archive, --active       runs in ACTIVE mode. (this will archive channels)"
  puts "    -h, --help, ?                 this handy help screen\n\n"
  exit(false)
elsif ["-d", "--dry-run"].include? ARGV[0]
  puts "Now running Slackr Archivr. \nYou have selected DRY-RUN mode."
  run_mode = "DRY"
elsif ["-a", "--live", "--active"].include? ARGV[0]
  puts "Now running Slackr Archivr. \nYou have selected ACTIVE mode."
  exit unless HighLine.agree("This will immediately archive channels. Make sure you've done a dry run first. Do you want to proceed? (yes/no)")
  puts "Proceeding..."
  run_mode = "ACTIVE"
elsif ["-n", "--notify"].include? ARGV[0]
  puts "Now running Slackr Archivr. \nYou have selected NOTIFY mode."
  exit unless HighLine.agree("This will immediately notify channels. Make sure you've done a dry run first. Do you want to proceed? (yes/no)")
  puts "Proceeding..."
  run_mode = "NOTIFY"
end

archiver_log.info { " ****** Beginning Slackr-Archiver in #{run_mode} Mode ****** " }
archiver_log.info { "****** Dry-Run is active. No Channels Will Be Archived! ******" } if run_mode == "DRY"

# import list of channels to archive arg
archiver_log.info { "Loading existing data..." }

# load existing data from csv
if File.exists?("slackr_channels.db")
  data = CSV.read("slackr_channels.db", { encoding: "UTF-8", headers: true, header_converters: :symbol, converters: :all})
  slackr_channels_db = data.map { |d| d.to_hash }
else
  archiver_log.warn { "Failed. slackr_channels.db not found!" }
  raise 'Failed. slackr_channels.db not found!'
end

archiver_log.info { "Checking for Whitelist..." }

# channel whitelist file is checked for and created if not found.
if File.exists?("whitelist.txt")
  channel_whitelist = CSV.read("whitelist.txt").flatten
  channel_whitelist.shift
  archiver_log.info { "Whitelist found and loaded." }
else
  File.open("whitelist.txt", "w") { |x| x.write("channel_name") }
  archiver_log.info { "Whitelist not found. Created blank file: whitelist.txt" }
end

# checking for existing of historical channel archive list
if File.exists?("slackr_archived_channels.log")
  archiver_log.info { "Historical Archived Channels List found." }
else
  File.open("slackr_archived_channels.log", "w") { |x| x.write("Channels Archived by Slackr Archiver:\n") }
  archiver_log.info { "Historical Archived Channels List not found. Created blank file: slackr_archived_channels.log" }
end

archiver_log.info { "Data loaded successfully." }
archiver_log.info { "Verifying Slack API Token and activating client." }

# activate API TOKEN in ENV for slack client
Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
  fail 'Missing ENV[SLACK_API_TOKEN]!' unless config.token
 end
client = Slack::Web::Client.new
archiver_log.info { "Slack API is accessible and active."}

archiver_log.info { "Checking for channels that haven't been touched for #{days_inactive_threshold} days." }

# check for channels that are 60 days inactive
slackr_channels_db.each do |x|
  channel_last_active_date = Time.parse(x[:channel_last_active_date])
  channel_name = x[:channel_name]
  channel_id = x[:channel_id]
  channel_days_inactive = Time.now.to_date.mjd - channel_last_active_date.to_date.mjd

  # if channel isn't in the whitelist, compare it's inactivity and add it to the appropriate array
  if !channel_whitelist.include?(channel_name)
    if channel_days_inactive >= days_inactive_threshold
      channels_to_archive.push({channel_name: channel_name, channel_id: channel_id})
      archiver_log.info { "===> [INACTIVE] :: [#{channel_name}] :: (#{channel_days_inactive}) days inactive :: [Channel to be Archived]"}
    else
      active_channels.push({channel_name: channel_name, channel_id: channel_id})
      notify_channels.push({channel_name: channel_name, channel_id: channel_id}) if channel_days_inactive >= notify_days_inactive_threshold
      archiver_log.info { "=> [#{channel_name}] :: (#{channel_days_inactive}) days inactive ::  [Active Channel]"}
    end
  else
    archiver_log.info { "=> [#{channel_name}] is [Whitelisted] :: (#{channel_days_inactive}) days inactive :: [Active Channel]"}
    active_channels.push({channel_name: channel_name, channel_id: channel_id})
  end
end

archiver_log.info {}
archiver_log.info {" Processing complete: "}
archiver_log.info {}
archiver_log.info {" Total Active Channels => #{active_channels.count} "}
archiver_log.info {" Total Channels Marked for Archival => #{channels_to_archive.count} "}
archiver_log.info {" Total Channels Marked to be Notified => #{notify_channels.count} "}
archiver_log.info {}

# Archive the channels here, or notify some, or not if dry-run
if run_mode == "ACTIVE"
  channels_to_archive.each do |channel|
    channel_id = channel[:channel_id]
    channel_name = channel[:channel_name]
    client.channels_archive(channel: channel_id)
    client.chat_postMessage(
      channel: channel_id,
      text: "Hello! This channel has been found ded and has been archived. Please contact IT with any memoriam or resurrection requests."
      )
    archiver_log.info { "[#{channel_name}] has been archived!" }
    # add it to the historical log of archived_channels
    File.open("slackr_archived_channels.log", "a") { |log| log.write("#{channel_name} was archived at #{run_date}\n") }
    # sleep for slack rate limiting
    sleep 1
  end
elsif run_mode == "DRY"
  archiver_log.info { "****** Dry-Run is active. No Channels Will Be Archived ******" }
  would_be_archived = channels_to_archive.map { |x| x[:channel_name] }
  archiver_log.info {" ****** Channels that would've been archived: #{would_be_archived} "}
elsif run_mode == "NOTIFY"
  notify_channels.each do |channel|
      channel_id = channel[:channel_id]
      channel_name = channel[:channel_name]
    client.chat_postMessage(
      channel: channel_id,
      text: "Hello! This channel looks like it hasn't been used in a while! Please note that it is now marked to be archived in 60 Days. Please contact IT to request this channel be whitelisted if you want to keep it."
      )
       archiver_log.info { "Notified #{channel_name} that the channel is now marked for death." }
       # sleep for slack rate limiting
      sleep 1
  end
else
  archiver_log.info { "Erm... Something strange happened."}
end

# for command line output, strip keys
channels_to_archive = channels_to_archive.map {|x| x[:channel_name]}
notify_channels = notify_channels.map {|x| x[:channel_name]}

archiver_log.info {}
archiver_log.info { " ****** Finished Slackr Archiver *#{run_mode}* Run ****** " }

puts "\n  Total Active Channels => #{active_channels.count} "
puts "  Total Channels Archived => #{channels_to_archive.count} " if ["ACTIVE", "DRY"].include?(run_mode)
puts "  Total Channels Notified => #{notify_channels.count} " if ["NOTIFY", "DRY"].include?(run_mode)
puts "\n  Channels Archived: #{channels_to_archive} \n\n" if ["ACTIVE", "DRY"].include?(run_mode)
puts "  Channels Notified: #{notify_channels} \n\n" if ["NOTIFY", "DRY"].include?(run_mode)
puts"See slackr_archiver.log for details."
puts "#{run_mode} Mode Run Complete. It's ok, no changes were made IRL.\n\n" if ["DRY"].include?(run_mode)
puts "#{run_mode} Mode Run Complete. \n\n" if ["NOTIFY", "ACTIVE"].include?(run_mode)


