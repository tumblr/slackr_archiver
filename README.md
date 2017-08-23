# SLACKR Auto-Archiver
v.1.0

A small app built to Auto-Archive Slack Channels when they don't have long retention times. 

This for a specific use case for when Slack is setup with a short default retention policy of 2 days. This has the effect of channels being labeled as "inactive" when in reality they may just have been quiet for a couple days.  To solve this, this app keeps a very simple "database" of channel history via the "Recon" script. It essentially keeps track of the last day a channel was active, but it checks every day and updates each channel's last active date if it was active, keeps the existing (old) date or sets the date to the current time for new channels. Once this "db" has been populated for a while, the "Archiver" script can be run to either notify idle channels or archive them. 

### Requirements

This was written in Ruby 2.4.1<br>
(but will probably work with older versions)<br>

<pre><code>Gems:<br>

require 'slack-ruby-client'<br>
require 'date'<br>
require 'csv'<br>
require 'logger'<br>
require 'highline/import'<br></code></pre>

#### SLACK API TOKEN

An `API TOKEN` is required to use this with your Slack instance. Go here to [create a new Slack App](https://api.slack.com/apps/new).

Once you create and name your app on your team, go to "OAuth & Permissions" to give it the following permission scopes:

- `channels:history`
- `channels:read`
- `channels:write`
- `chat:write:bot`
- `chat:write:user`
- `emoji:read`
- `users:read`

After saving, you can copy the OAuth Access Token value from the top of the same screen. It probably starts with `xox`.  This will need to be [exported to your system's `ENVIRONMENT`](https://www.cyberciti.biz/faq/set-environment-variable-linux/) eg: `export SLACK_API_TOKEN=xox....` 

## Usage

#### Recon_Slackr

The **Recon** app creates a file called `slackr_channels.db`.  It stores each public channels last active message date. It currently pulls the last 3 messages per channel and evaluates them. This can be changed as the `channel_count` variable in the recon script if needed.

It will also create a copy of the last day's run db to use as a comparison and backup, <code>slackr_channels.db.last</code>. If it finds that a message has a last active date in the db, it won't erase it and start it fresh as if the channel is new. 

**Recon needs to be setup to run daily via cron.** Check out [Cron Tag Guru](https://crontab.guru/) if you need help with setting up Crons. 

An example: `0 1 * * * cd <path>/<to>/<app> && ruby <path>/<to>/<app>/recon_slackr.rb`


#### Archiver_Slackr

The **Archiver** app can be used to either:

+ Perform a **Dry-Run**. This should always be done first. 
+ **Archive** channels with 60+ days of inactivity
+ **Notify** dead channels with 30+ days of inactivity
  + To edit the message text, you need to edit <code>archiver_slackr.rb</code>
  + You can alter the Inactivity time in <code>archiver_slackr.rb</code>

<pre><code>
Usage:  archiver_slackr <flag>
    -d, --dry-run                 runs in DRY-RUN mode (do this first! no channels will be archived)
    -n, --notify                  runs in NOTIFY mode. (sends a polite message to any channels that are 30 days inactive (but less than 60)
    -a, --archive, --active       runs in ACTIVE mode. (this will archive channels)
    -h, --help, ?                 this handy help screen
    </code></pre>

An example would be to run `ruby archiver_slackr -d` to do a dry run.

### Whitelist

There is a whitelist file used to prevent specific channels from being archived.  Edit the file `whitelist.txt` for any changes.  If the file is missing it will be created upon first run.

### Blacklists

Within the `Recon` script there are two "Blacklist" arrays.  Anything in these blacklists will not be considered as activity in a channel and will instead be ignored. One is for [`Channel Subtypes` (the kind of message)](https://api.slack.com/events/message), the other is for specific `Users`.  ***It is required that your Slackr-Archiver user be listed in the User blacklist.*** If you don't update the Users blacklist, then whenever you notify a channel, it will reset it's last active date to that day.

### Logging

All activity is logged in the files: 
+ `slackr_archiver.log` - Detailed logs of any archiver run, including dry runs. 
+ `slackr_archived_channels.log` - A list of all channels that were archived and the date it happened. Once a channel is archived, it will no longer be in the DB. The previous run is saved as a `.last` file.
+ `slackr_channels.db` - This is the CSV "db" file created by Recon and used by Archiver. 
+ `slackr_recon.log` - Logs the activity of the Recon script.

### Possible Future updates: 
+ Allow message to be specified on the command line
+ Allow number of recent messages parsed to be specified on command line
