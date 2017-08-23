#!/usr/bin/env ruby

require 'slack-ruby-client'
require 'date'
require 'csv'
require 'logger'

# logging options
recon_log = Logger.new("slackr_recon.log", 6, 50240000)
recon_log.datetime_format = '%Y-%m-%d %H:%M:%S'
recon_log.formatter = proc do |severity, datetime, progname, msg|
   "#{datetime} -- :  #{msg}\n"
end

recon_log.info { "***** Beginning Recon run. ***** "}

puts "Beginning Recon run."

# Blacklist: add to this array any message subtypes you don't want to include (check slack's api for info)
# currently not including 'bot_message' since we have lots of channels that use mostly or only
# to make sure a message by a user is ignored, add it to the username_blacklist array.
subtype_blacklist = ['channel_leave', 'channel_join', 'channel_name', 'channel_unarchive', 'channel_purpose', 'channel_topic']
username_blacklist = ['Slackr-Archiver']
channel_count = 3

# don't edit the below
channels = []
prev_run_data = []
active_channels = []
idle_channels = []
new_channels = []


recon_log.info { " Verifying existence of log files."}
# load existing data from csv into array of hashes
if File.exists?("slackr_channels.db")
  File.rename("slackr_channels.db", "slackr_channels.db.last")
  data = CSV.read("slackr_channels.db.last", { encoding: "UTF-8", headers: true, header_converters: :symbol, converters: :all})
  prev_run_data = data.map { |d| d.to_hash }
  recon_log.info { "Log file found.  Renamed and loaded."}
elsif File.exists?("slackr_channels.db.last")
  recon_log.info { " Log file NOT found. .last backup file found and loaded instead."}
  data = CSV.read("slackr_channels.db.last", { encoding: "UTF-8", headers: true, header_converters: :symbol, converters: :all})
    prev_run_data = data.map { |d| d.to_hash }
else
  recon_log.info { " No log files found. Proceeding with no historical data."}
  prev_run_data = [{ "channel_id" => "00" }]
end

recon_log.info { "Verifying Slack API Token and activating client."}
# load env api token
Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
  fail 'Missing ENV[SLACK_API_TOKEN]!' unless config.token
end
client = Slack::Web::Client.new
recon_log.info { "Slack API is accessible and active."}

recon_log.info {"Getting list of all non-archived channels."}
# get all active (non-archived) channels so we can get their id's
non_archived_channels = client.channels_list.channels.select { |data| !data.is_archived }

recon_log.info {"Checking channels for recent messages. Checking the last #{channel_count} messages."}
# for each channel, get it's ID and some other identifiers
non_archived_channels.each do |channel|
  channel_id = channel['id']
  channel_name = channel['name']
  channel_history = client.channels_history(channel: channel_id, count: channel_count)
  recent_msg_dates = []

  # grab the last 3 messages from each channel and see if it's new.
  channel_history['messages'].each do |msg|
    msg_date = msg['ts']
    msg_text = msg['text']
    msg_subtype = msg['subtype']
    msg_username = msg['username']
    msg_hdate = Time.at(msg_date.to_i).to_datetime

    if !username_blacklist.include?(msg_username)
      if !subtype_blacklist.include?(msg_subtype)
        if msg_hdate >= Time.now - 48.hours
           recent_msg_dates.push(msg_hdate)
        end
      end
    end
  end

if !recent_msg_dates[0].nil?
  recon_log.info { "[ACTIVE]: [#{channel_name}] looks active in the last 48 hours. Updating date in db."}
  active_channels.push({channel_name: channel_name})
end

# gets the first item from the array because slack outputs events in time order, newest first.
channel_last_active_date = recent_msg_dates[0]

# if a channel's last active date is nil, check the db for a date, if there is none, set it today.
# if there is an existing date in the db, set channel_last_active_date to the date in the db.

prev_run_data_arr = prev_run_data.select { |x| x[:channel_id] == channel_id }

if !prev_run_data_arr[0].nil?
  prev_run_data_hash = prev_run_data_arr[0].to_hash
  channel_prev_run_active_date = prev_run_data_hash[:channel_last_active_date]
end

# if the channel has no previous or new activity, sets date to now.
if channel_last_active_date.nil?
  if channel_prev_run_active_date.nil?
    channel_last_active_date = Time.now
    new_channels.push({channel_name: channel_name})
    recon_log.info {"[NEW]: [#{channel_name}] looks to have no previous activity. Likely a new channel. Setting last active date to current run date: (#{channel_last_active_date})"}
  else
   channel_last_active_date = channel_prev_run_active_date
   idle_channels.push({channel_name: channel_name})
   recon_log.info {"[IDLE]: [#{channel_name}] looks to have no recent activity, but it did previously.  Keeping old date in DB. (#{channel_last_active_date})"}
  end
end

# send the results to the channels array for output later
channels.push({channel_name: channel_name, channel_id: channel_id, channel_last_active_date: channel_last_active_date})

# sleep for Slack's API rate limit of 1 call per second.
sleep 1.5
end

recon_log.info { "Updating DB file."}

# write to csv, channel name, channel id, last message date
CSV.open("slackr_channels.db", "w") do |csv|
  csv << channels.first.keys
  channels.each do |channel|
    csv << channel.values
  end
end

recon_log.info {"Processing complete."}
recon_log.info {"Processed #{channels.count} channels. "}
recon_log.info {}
recon_log.info {"Active Channels Updated: #{active_channels.count}"}
recon_log.info {"New Channels Added: #{new_channels.count}"}
recon_log.info {"Idle Channels (date not updated): #{idle_channels.count}"}
recon_log.info {}
recon_log.info {"***** Recon run done ***** "}
puts "\n\nActive Channels Updated: #{active_channels.count}"
puts "New Channels Added: #{new_channels.count}"
puts "Idle Channels (date not updated): #{idle_channels.count}"
puts "Processed #{channels.count} total channels.\n\n"
puts "Done with Recon run!"
