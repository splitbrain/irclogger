# <?php die() ?>
# configuration file for irc logger
#
#

# DB access used by frontend and logger
db_host = 127.0.0.1
db_user = wiki
db_pass = w1k1
db_name = wiki
db_table = messages

# where is the frontend installed to?
baseurl = http://irc.dokuwiki.org/

# log files
debug_log=/var/log/irclog/irclog-debug.log
error_log=/var/log/irclog/irclog.log

# activate debug mode (0 = off, 1 = on)
debug=0

# IRC data used by logger only
irc_host = irc.freenode.net
irc_port = 6666
irc_chan = #dokuwiki
irc_nick = dokubot
irc_name = logs available at irc.dokuwiki.org
irc_pass = d0kU
#irc_hello    = I'm now logging this channel
irc_hello    = 
irc_warning  = 
irc_bye      = Unfortunately I have to leave you now. So don't do anything silly while I'm not here.
# reconnect delay. if 0 no reconnect is attempted
irc_reconnect = 4

# pid file path for forked daemon
pidfile=/var/run/irclog-fork.pid
