#!/bin/bash

# --------
# SETTINGS
CHAT_ID=""
BOT_TOKEN=""
# --------

old=$(basename "/$sonarr_episodefile_previousrelativepaths")
new=$(basename "/$sonarr_episodefile_relativepaths")

MESSAGE="Episode
\`$old\`
Renamed to
\`$new\`"

curl -sSX POST -H 'Content-Type: application/json' \
     "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
     -d "{\"chat_id\": \"$CHAT_ID\", \"text\": \"$MESSAGE\", \"parse_mode\": \"markdown\" \"disable_notification\": true}" \
     -o /dev/null
