puts "Loading #{__FILE__}"
# Put overrides/additions in '_irbrc' (see _irbrc.example)
IRB.conf[:HISTORY_FILE] = "tmp/.irb_history"
IRB.conf[:HISTORY] = -1 # all of it
