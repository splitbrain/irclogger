#!/usr/bin/perl
# TODO:
#   implement clean test functions
#       db connection
#       irc connection
#       db table
#       db rights
#       channel connection (sending channel commands like 'names' results in recieving irc_353 & irc_366 and return of null)
#   implement more error-handling
#       db not connected
#       irc not connected
#       insufficient rights on db
#   add documentation using pod
#   add multichannel support
#   improve today & yesterday filter of webinterface
#
#
use strict;
use warnings;
use POE qw(Component::IRC Component::IRC::State Component::IRC::Plugin::AutoJoin);
use DBI;
use Data::Dumper;
use Getopt::Std;
use POSIX qw(setsid);
use POSIX ();
use Digest::MD5 qw(md5_hex);
use Cwd qw(abs_path);

my $script = abs_path($0);
$script =~ /^(.+[\\\/])[^\\\/]+[\\\/]*$/;
my $scriptdir= $1 || "./";
my $configfile = $scriptdir . 'irclog.config.php';
my $specialfile = $scriptdir . "irclog.special.pl";
my %conf;
my $dbh;
my $irch;
my $chksum;
my %opts;
my $action;

sub usage {
    print "This script controls an irc logging bot with command support.
Available options:
  -c - config file to use
  -h - this help
  -r - reload configurations and reconnects to irc and database if needed
  -s - start bot
  -t - check whether the bot is still running
  -x - stop bot\n";
}

sub loadconfig($) {
    my $file = shift();
    my %conf;
    open(FILE,$file) || die "failed to open config $file";
    my @lines = <FILE>;
    close FILE;
    return %conf if (!scalar(@lines));

    foreach my $line (@lines) {
        #ignore comments
        $line =~ s/^#.*$//;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if($line eq '');
        my @data = split(/\s*=\s*/,$line,2);
        $conf{$data[0]} = $data[1];
    }
    return %conf;
}

sub checklib($) {
    my $file = shift;
    if ( defined($file) ) {
        if ( not -r $file ) {
            log_error("Couldn't read file $file: no permission.");
            return 0;
        }
        if ( system("/usr/bin/perl -c \"$file\"") != 0 ) {
            log_error("Syntax error in file $file. See messages above.");
            return 0;
        }
    }
    return 1;
}

sub log_error($) {
    my $msg = shift();
    open(my $file, '>&STDERR') or die $!;
    print { $file } "@{ [time] } $msg\n";
    close($file);
}

sub log_debug($) {
    if ( $conf{'debug'} == 1 ) {
        my $msg = shift();
        open(my $file, '>>'. $conf{'debug_log'}) or die $!;
        print { $file } "@{ [time] } $msg\n";
        close($file);
    }
}

sub log_db($$$) {
    my $nick = shift;
    my $type = shift;
    my $msg = shift;
    if ( "$nick" eq "$conf{'irc_chan'}" ) {
        $type = 'public';
    }
    log_debug("Logging information into database: Nick = $nick; Type = $type; msg = $msg");
    $dbh->do("INSERT INTO $conf{'db_logtable'} (user,type,msg) VALUES (?,?,?)",undef,$nick, $type, $msg) or ( log_error("Couldn't write to table. $dbh->errstr") and return 0 );
}

sub connect_db {
    log_debug("Connecting to database.");
    my $dbh = DBI->connect("DBI:mysql:database=$conf{db_name};host=$conf{db_host};port=$conf{db_port}", $conf{db_user}, $conf{db_pass}, { AutoCommit => 1 }) || log_error("failed to open DB connection: $DBI::errstr");
    $dbh->{mysql_auto_reconnect} = 1;
    return $dbh;
}

sub disconnect_db {
    log_debug("Disconnecting to database.");
    my $rc = $dbh->finish() or log_error("Error while finishing transactions: $dbh->errstr");
    $dbh->disconnect() or log_error("Error while disconnecting: $dbh->errstr");
}

sub connect_irc {
    log_debug("Connecting to irc.");
    my $irch;
    do {
        $irch = POE::Component::IRC::State->spawn(
            nick => $conf{'irc_nick'},
            ircname => $conf{'irc_name'},
            server  => $conf{'irc_host'},
            port => $conf{'irc_port'},
            password => $conf{'irc_pass'},
            debug => $conf{'debug'},
            plugin_debug => $conf{'debug'},
            nodns => 1,
            whojoiners => 0,
         ) or log_error("Error while connecting to IRC $!. Will retry in 10 seconds");
        sleep 10;
    } until (defined($irch));
    return $irch;
}

sub disconnect_irc($) {
    log_debug("Disconnecting from irc.");
    my $irch = shift;
    $irch->yield('shutdown', $conf{'irc_bye'});
    log_debug("Disconnected from irc.");
}

sub filemd5($) {
    my $file = shift;
    log_debug("Generating MD5 sum of $file.");
    my $ctx = Digest::MD5->new;
    open(my $spfh, '<' . $file) or log_error("Couldn't open file $file for MD5 calculation: $!");
    binmode($spfh);
    $ctx->addfile($spfh);
    my $chksum = $ctx->hexdigest;
    close($spfh);
    undef $ctx;
    log_debug("MD5 sum of $file generated: $chksum.");
    return $chksum;
}

sub store_msg($$$) {
    my $irch = shift;
    my $msg = shift;
    my $nick = shift;
    my $rcpt = get_recipient($msg);
    if ( not defined($rcpt) or ( defined($rcpt) and $rcpt eq '' ) ) {
        return 0;
    }
    if ( $rcpt =~ /\d+/ ) {
        $irch->yield('privmsg', $nick, "Couldn't store your message because there were $rcpt nicks known by database.");
    } else {
        log_debug("Try storing message for $rcpt.");
        my @channels = $irch->nick_channels($rcpt);
        log_debug("Found $rcpt in channels " . Dumper(@channels));
        if ( $#channels == -1 ) {
            save_msg($nick, $rcpt, $msg);
            $irch->yield('privmsg', $nick, "Stored your message for $rcpt.");
        }
    }
}

sub push_msgs($$) {
    my $irch = shift;
    my $nick = shift;
    log_debug("Getting messages stored for $nick");
    my $msgs = get_msgs($nick);
    foreach my $key (keys $msgs) {
        log_debug("Got following data of database: " . Dumper($msgs->{$key}));
        my $datetime = ( split(/:\d+$/, $msgs->{$key}->{dt}) )[0];
        my @id = $dbh->selectrow_arrayref("SELECT id from $conf{'db_logtable'} where dt = '$datetime' and msg = '$msgs->{$key}->{msg}'") or log_error("Couldn't get id. $dbh->errstr");
        log_debug("ID: " . Dumper(@id));
        $irch->yield('privmsg', $nick, "Hi, you were contacted by $msgs->{$key}->{sender}.");
        $irch->yield('privmsg', $nick, "The message was: $msgs->{$key}->{msg}");
        $irch->yield('privmsg', $nick, "For reference have a look at IRC-log: $conf{'baseurl'}/index.php?d=" . (split(/ /,$msgs->{$key}->{dt}))[0] . "#msg$id[0][0]");
        log_debug("Deleting data from database.");
        $dbh->do("DELETE FROM $conf{'db_storetable'} WHERE id = ?", undef, $msgs->{$key}->{id});
    }
}

sub save_msg($$$) {
    my $sender = shift;
    my $recipient = shift;
    my $msg = shift;
    log_debug("Saving message: Sender = $sender; Recipient = $recipient; Message = $msg");
    $dbh->do("INSERT INTO $conf{'db_storetable'} (sender,recipient,msg) VALUES (?,?,?)",undef,$sender, $recipient, $msg) or log_error("Couldn't write to table. $dbh->errstr");
}

sub get_recipient($) {
    my $msg = shift;
    my $rcpt = ($msg =~ m/^\s*@(:?[^ ]+)\s.*$/)[0];
    if ( defined($rcpt) and $rcpt ne '' ) {
        log_debug("Recipient for stored message = $rcpt");
        my @known_nicks = @{ $dbh->selectall_arrayref("SELECT user from `$conf{'db_logtable'}` where user = '$rcpt' group by user", { Slice => {}}) } or log_error("Couldn't prepare statement." . $dbh->errstr);
        log_debug("Found " . ( $#known_nicks + 1 ) . " entries in database with $rcpt. " . Dumper(@known_nicks));
        if ( $#known_nicks + 1 == 1 ) {
            return $known_nicks[0]->{'user'};
        } else {
            return $#known_nicks + 1;
        }
    }
}

sub get_msgs($) {
    my $nick = shift;
    my $msgs;
    my $slh = $dbh->prepare("SELECT * from `$conf{'db_storetable'}` where recipient = '$nick'");
    $slh->execute;
    $msgs = $slh->fetchall_hashref('id');
    return $msgs;
}

=head1 privmsg_irc()

Arguments: irc-handler, target channel, message

Returns  : none

Sends given message as private message to given chanel.

=cut

sub privmsg_irc($$$) {
    my $irch = shift;
    my $target = shift;
    my $msg = shift;
    if ( defined($msg) and $msg ne '' ) {
        $irch->yield('privmsg', $target, $msg);
        log_db($target, 'privmsg', $msg);
    }
}

=head1 bootup()

Arguments: none

Returns  : none

This is one of the main functions and starts the irclogger.

It also registers the following process signals:

=over 1

=item L<TERM|/"sigtrap TERM"> => stops irclogger

=item L<USR1|/"sigtrap USR1"> => reload configuration files and restart if needed

=item L<USR2|/"sigtrap USR2"> => run function tests

=back

=cut

sub __bootup {
    log_debug("Starting main fork.");
    umask 0;
    chdir("/");
    open(STDIN, '</dev/null') or die "Can't read /dev/null: $!";
    open(STDOUT, '>/dev/null');
    open(STDERR, '>/dev/null');
    defined(my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        log_error("PID of forked main process is $pid.");
        open(my $pidfile, '>', $conf{'pidfile'}) or ( log_error("Couldn't open PID file $conf{'pidfile'}: $!") and return 0 );
        print { $pidfile } $pid;
        close($pidfile);
        unset $pidfile;
    }
    setsid or die "Can't start a new session: $!";
    while($pid == 0) {
        use strict;
        use warnings;
        if ( $conf{'debug'} == 1 ) {
            open(STDOUT, ">>$conf{'debug_log'}") or die "Can't write to $conf{'debug_log'}: $!";
        } else {
            open(STDOUT, ">/dev/null");
        }
        open(STDERR, ">>$conf{'error_log'}") or die "Can't write to $conf{'error_log'}: $!";
        log_error("Started main process.");

        $chksum = filemd5($specialfile);

        checklib($specialfile) and require $specialfile;

        $dbh = connect_db;
        defined($dbh) or ( log_error("Connection to database failed with error: $DBI::errstr") and exit 3 );
        $irch = connect_irc;

=head2 sigtrap TERM

Signal handler for TERM.

On SIGTERM the following actions are done:

=over 1

=item message is logged into error-log

=item configured Bye-message is logged into database

=item irc-handler runs shutdown command to log out of irc properly

=item disconnect_db() is run to finish db connection properly

=item pid file and test file are removed

=item program exits with code 0

=back

=cut
        
        use sigtrap 'handler', sub {
            log_error("Stopping daemon.");
            privmsg_irc($irch, $conf{'irc_chan'}, $conf{'irc_bye'});
            sleep 2;
            $irch->yield('shutdown', 'Good (UGT) Night');
            disconnect_db();
            open(FILE,$conf{'pidfile'} . ".monitor") || die "failed to open pid file $conf{'pidfile'}.monitor";
            my @lines = <FILE>;
            close FILE;
            log_debug("Stopping selfmonitoring with PID $lines[0]");
            kill('TERM', $lines[0]);
            unlink($conf{'pidfile'});
            unlink($conf{'pidfile'} . ".monitor");
            unlink($conf{'testfile'});
            exit 0;
        }, 'TERM';

=head2 sigtrap USR2

Signal handler for USR2.

On SIGUSR2 all the following functionalities are tested:

=over 1

=item IRC connection

=item login status for IRC

=item join status for configured channels

=item database connection

=item execution status for SQL commands on database

=back

=cut

        use sigtrap 'handler', sub {
            my $irc_connected = 2;
            my $irc_logged_in = 2;
            my $irc_channel = 3;
            my $db_connected = 2;
            my $db_execute = 2;
            log_error("Testing daemon.");
            if ( $irch->connected() ) {
                log_debug("IRC client is connected.");
                $irc_connected = 1;
            }
            if ( $irch->logged_in() ) {
                log_debug("IRC client is logged in.");
                $irc_logged_in = 1;
            }
            my $names = $irch->yield('names', $conf{'irc_chan'});
            log_debug(Dumper($irch->yield('names', $conf{'irc_chan'})));
            if ( defined($names) ) {
                log_debug("Output of irc_channel check: $names");
                log_debug("Bot connected to the channel $conf{'irc_chan'}");
                $irc_channel = 1;
            }
            if ( $dbh->ping() ) {
                log_debug("Bot connected to database");
                $db_connected = 1;
            }
            my $slh = $dbh->prepare("SELECT 'test'");
            $slh->execute();
            my @testres = $slh->fetchrow_array;
            if ( "$testres[0]" eq "test" ) {
                log_debug("Test SQL-'select' succeeded.");
                $db_execute = 1;
            }
            open(my $fh, '>' . $conf{'testfile'});
            print {$fh} "irc_connected=$irc_connected\nirc_logged_in=$irc_logged_in\nirc_channel=$irc_channel\ndb_connected=$db_connected\ndb_execute=$db_execute";
            close($fh);
        }, 'USR2';
        use sigtrap 'handler', sub {
            my $reconnect = 0;
            log_error("Reloading config file $configfile");
            my %confnew = loadconfig($configfile) or log_error("Error loading $configfile");
            log_debug("Checking for changes in config file.");
            foreach my $param (keys %confnew) {
                if ( "$confnew{$param}" ne "$conf{$param}" ) {
                    log_debug("Found change for $param: old = $conf{$param} new = $confnew{$param}");
                    if ( $param =~ /^db_/ or $param =~ /^irc_/ ) { $reconnect = 1 }
                    %conf = %confnew;
                }
            }
        
            if ( $reconnect == 1 ) {
                log_debug("Restarting bot because of changes for database or irc options.");
                defined(my $pid = fork) or die "Can't fork: $!";
                setsid or die "Can't start a new session: $!";
                while(1) {
                    system('/bin/bash', '-c', "$0 -c $configfile -x");
                    system('/bin/bash', '-c', "$0 -c $configfile -s");
                }
            }
        
            my $chksum_new = filemd5($specialfile);

            log_debug("Checking for changes in special file. old MD5 = $chksum; new MD5 = $chksum_new");
            if ( "$chksum" ne "$chksum_new" and checklib($specialfile) ) {
                log_debug("Reloading $specialfile.");
                delete $INC{$specialfile};
                require $specialfile;
            }
        }, 'USR1';
        POE::Session->create(
            package_states => [
                main => [ qw( _default _start irc_001 irc_join irc_msg irc_nick irc_part irc_public irc_quit ) ],
            ],
            heap => { irch => $irch },
        );
        POE::Kernel->run();
    }
    if ( $conf{'debug'} == 1 ) {
        open(STDOUT, ">>$conf{'debug_log'}") or die "Can't write to $conf{'debug_log'}: $!";
    } else {
        open(STDOUT, ">/dev/null");
    }
    open(STDERR, ">>$conf{'error_log'}") or die "Can't write to $conf{'error_log'}: $!";
    log_debug("Finished main process loop.");
    exit;
}

sub __selfmonitor {
    if ( $conf{'selfmonitor'} == 1 ) {
        log_debug("Starting selfmonitoring fork.");
        umask 0;
        chdir("/");
        open(STDIN, '</dev/null');
        open(STDOUT, '>/dev/null');
        open(STDERR, '>/dev/null') or die "Can't write to $conf{'monitor_log'}: $!";
        defined(my $pid = fork) or die "Can't fork: $!";
        if ($pid) {
            log_error("PID of forked selfmonitoring process is $pid.");
            my $pidfile = $conf{'pidfile'} . ".monitor";
            open(my $pfh, '>', $pidfile) or log_error("Couldn't open PID file $pidfile: $!");
            print { $pfh } $pid;
            close($pfh);
            unset($pidfile);
        }
        setsid or die "Can't start a new session: $!";
        if ($pid == 0) {
            sleep 20;
            log_debug("Starting selfmonitoring loop.");
            if ( $conf{'debug'} == 1 ) {
                open(STDOUT, ">>$conf{'monitor_debug_log'}") or die "Can't write to $conf{'monitor_debug_log'}: $!";
            } else {
                open(STDOUT, ">/dev/null");
            }
            open(STDERR, ">>$conf{'monitor_log'}") or die "Can't write to $conf{'monitor_log'}: $!";
            log_error("Started selfmonitoring.");
            
            while (1) {
                sleep 10;
                my $testres = __test();
                log_debug("Test result: $testres of monitor $pid");
                if ( $testres == 2 ) {
                    system('/bin/bash', '-c', "$0 -c $configfile -x");
                    system('/bin/bash', '-c', "$0 -c $configfile -s");
                    exit;
                }
            }
        }
    }
}

sub __stop {
    open(my $pidfile, '<' . $conf{'pidfile'}) or ( log_error("Couldn't open PID file $conf{'pidfile'}: $!") and print "Couldn't open PID file $conf{'pidfile'}: $!" );
    my $pid = <$pidfile>;
    kill('TERM', $pid);
    return 0;
}

sub __reload {
    open(my $pidfile, '<' . $conf{'pidfile'}) or ( log_error("Couldn't open PID file $conf{'pidfile'}: $!") and print "Couldn't open PID file $conf{'pidfile'}: $!" );
    my $pid = <$pidfile>;
    kill('USR1', $pid);
    return 0;
}

# Returns:
#  0 - success
#  1 - can't find process
#  2 - error which needs to restart the bot
#  3 - bot isNn't connected to channel
sub __test {
    my $return = 0;
    open(STDERR, ">>$conf{'monitor_log'}") or die "Can't write to $conf{'monitorr_log'}: $!";
    open(my $pidfile, '<' . $conf{'pidfile'}) or ( log_error("Couldn't open PID file $conf{'pidfile'}: $!") and $return = 1 );
    if ( $return == 0 ) {
        my $pid = <$pidfile>;
        my $cnt = kill('USR2', $pid);
        sleep 1;
        if ( $cnt > 0 and -r $conf{'testfile'} ) {
            open(my $fh, '<' . $conf{'testfile'});
            my @lines = <$fh>;
            close($fh);
            foreach my $line (@lines) {
                my @data = split(/\s*=\s*/,$line,2);
                if ($data[1] != 1) {
                    log_debug("Test for $data[0] failed.");
                    print "Test for $data[0] failed.\n";
                    if ($return == 0 or $return > $data[1] ) {
                        $return = $data[1];
                    }
                }
            }
        }
    }
    return $return;
}

sub _start {
    my $heap = $_[HEAP];
    my $irch = $heap->{irch};
    my @channels = ( $conf{'irc_chan'}, );
    $irch->plugin_add('AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new(
            Channels => \@channels ,
            RejoinOnKick => 1,
            Rejoin_delay => $conf{'irc_reconnect'},
        )
    );
    $irch->yield( register => 'all' );
    $irch->yield( connect => { } );
    log_error("Bot started and connected.");
    return;
}

sub _default {
    my ($event, $args) = @_[ARG0 .. $#_];
    my @output = ( "@{ [time] } $event: " );

    for my $arg (@$args) {
        if ( ref $arg eq 'ARRAY' ) {
            push( @output, '[' . join(', ', @$arg ) . ']' );
        }
        else {
            push ( @output, "'$arg'" );
        }
    }
    print join ' ', @output, "\n";
    return;
}

sub irc_001 {
    my $sender = $_[SENDER];
    my $irch = $sender->get_heap();
    print "Connected to ", $irch->server_name(), "\n";
    return;
}

=head1 irc_353()

Handles list returned by IRC-command 'names'.

This command is used by selfmonitor to check channel connectivity.

=cut

=head1 irc_366()

Handles the message ':End of NAMES list'.

ATM nothing should be done.

=cut

sub irc_366 {
    return 1;
}

sub irc_join {
    my ($sender, $who, $channel) = @_[SENDER, ARG0, ARG1];
    my $irch = $sender->get_heap();
    my ($nick, $host) = split /!/, $who;
    log_db($nick, 'join', "$nick ($host) has entered the channel");
    if ( defined($conf{'irc_warning'}) and $conf{'irc_warning'} ne '' ) {
        log_db($conf{'irc_nick'}, 'privmsg', $conf{'irc_warning'});
        privmsg_irc($irch, $nick, $conf{'irc_warning'});
    }
    if ( defined($conf{'irc_newcomer'}) and $conf{'irc_newcomer'} ne '' ) {
        log_db($conf{'irc_nick'}, 'privmsg', $conf{'irc_newcomer'});
        privmsg_irc($irch, $nick, $conf{'irc_newcomer'});
    }
    if ( $nick ne $conf{'irc_nick'} ) {
        push_msgs($irch, $nick);
    }
}

sub irc_msg {
    my ($sender, $who, $rcpnick, $msg, $identified) = @_[SENDER, ARG0 .. ARG3];
    my $irch = $sender->get_heap();
    my $nick = ( split /!/, $who )[0];
    privmsg_irc($irch, $nick, "Thanks for talking to me but I'm just a humble ircbot of $conf{'irc_chan'}.");
    privmsg_irc($irch, $nick, "If you want to know more about me write in the channel 'dokubot help'.");
}

sub irc_nick {
    my ($who, $newnick) = @_[ARG0, ARG1];
    my $nick = ( split /!/, $who )[0];
    log_db($nick, 'nick', "$nick is now known as $newnick");
}

sub irc_part {
    my ($who, $channel, $partmsg) = @_[ARG0 .. ARG2];
    defined($partmsg) or $partmsg = 'none';
    my ($nick, $host) = split /!/, $who;
    log_db($nick, 'part', "$nick ($host) has left the channel ($channel) with message '$partmsg'");
}

=head1 irc_public()

Arguments: none

Returns  : none

This function is called by IRC module for each message with type 'public'. Thus each message on a channel.

It logs the message in the database, runs L<C<special()>|/"special"> and runs L<C<store_msg()>|/"store_msg()">.

=cut

sub irc_public {
    my ($sender, $who, $channels, $msg, $identified) = @_[SENDER, ARG0 .. ARG3];
    my $irch = $sender->get_heap();
    my $nick = ( split /!/, $who )[0];
    log_debug("irc_public -> Sender: $sender ; Nick: $nick ; CHannels: " . Dumper($channels) . " ; Msg: $msg");
    if (not log_db($nick, 'public', $msg)) {
        foreach my $chan ($channels) {
            privmsg_irc($irch, $chan, 'My database ditched me. Please contact the bot administrator.');
        }
    }
    if (exists(&special)) {
        special($irch, \%conf, $msg, $nick)
    } else {
        privmsg_irc($irch, $conf{irc_chan}, 'Currently I have an amnesia. Please contact the bot administatrator.');
    }
    store_msg($irch, $msg, $nick);
}

sub irc_quit {
    my ($who, $partmsg, $channel) = @_[ARG0 .. ARG2];
    defined($partmsg) or $partmsg = 'none';
    my ($nick, $host) = split /!/, $who;
    log_db($nick, 'quit', "$nick ($host) has quit ($partmsg)");
}

# Options:
#  c - configfile
#  h - help
#  r - reconnect to irc and database
#  s - start daemon
#  t - test wether daemon is running
#  x - stop daemon
if (getopts('c:hrstx', \%opts)) {
    if ($opts{'c'}) {
        $configfile = $opts{'c'};
    }
    if ($opts{'h'}) {
        usage;
        exit 0;
    }
    if ($opts{'r'}) {
        $action = 'reload';
    }
    if ($opts{'s'}) {
        $action = 'bootup';
    }
    if ($opts{'t'}) {
        print "Running selftest. The return code is one of the following:\n";
        print "  0 - success\n";
        print "  1 - can't find process\n";
        print "  2 - error which needs to restart the bot\n";
        print "  3 - bot isn't connected to channel\n";
        $action = 'test';
    }
    if ($opts{'x'}) {
        $action = 'stop';
    }
} else {
    usage;
    exit 1;
}

if (not defined($action)) {
    print "Running selftest. The return code is one of the following:\n";
    print "  0 - success\n";
    print "  1 - can't find process\n";
    print "  2 - error which needs to restart the bot\n";
    print "  3 - bot isn't connected to channel\n";
    $action = 'test';
}

%conf = loadconfig($configfile);

log_debug("Running action $action");
my $ret = eval '__' . $action;
if ( $action eq 'bootup' ) { __selfmonitor(); }
exit $ret if defined($ret);

# vim:et:ts=4
