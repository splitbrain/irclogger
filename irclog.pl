#!/usr/bin/perl
use strict;
use warnings;
use POE qw(Component::IRC Component::IRC::State Component::IRC::Plugin::AutoJoin);
use DBI;
use Data::Dumper;
use Getopt::Std;
use POSIX qw(setsid);
use POSIX ();
use Digest::MD5 qw(md5_hex);

$0=~/^(.+[\\\/])[^\\\/]+[\\\/]*$/;
my $scriptdir= $1 || "./";
my $configfile = $scriptdir . 'irclogger.config.php';
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

sub log_error($) {
    my $msg = shift();
    open(my $file, '>>', $conf{'error_log'}) or die $!;
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
    $dbh->do("INSERT INTO $conf{'db_logtable'} (user,type,msg) VALUES (?,?,?)",undef,$nick, $type, $msg) or log_error("Couldn't write to table. $dbh->errstr");
}

sub save_msg($$$) {
    my $sender = shift;
    my $recipient = shift;
    my $msg = shift;
    log_debug("Saving message: Sender = $sender; Recipient = $recipient; Message = $msg");
    $dbh->do("INSERT INTO $conf{'db_storetable'} (sender,recipient,msg) VALUES (?,?,?)",undef,$sender, $recipient, $msg) or log_error("Couldn't write to table. $dbh->errstr");
}

sub db_connect {
    log_debug("Connecting to database.");
    my $dbh = DBI->connect("DBI:mysql:database=$conf{db_name};host=$conf{db_host}",
                          $conf{db_user}, $conf{db_pass}) || log_error("failed to open DB connection");
    $dbh->{mysql_auto_reconnect} = 1;
    return $dbh;
}

sub db_disconnect {
    log_debug("Disconnecting to database.");
    my $rc = $dbh->finish() or log_error("Error while finishing transactions: $dbh->errstr");
    $dbh->disconnect() or log_error("Error while disconnecting: $dbh->errstr");
}

sub get_recipient($) {
#    my $msg = shift;
#    my $rcpt = $msg =~ m/^
#    my $slh = $dbh->do("SELECT user from $conf{'db_logtable'} where user like %$rcpt% group by user");
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
    my $ctx = Digest::MD5->new;
    open(my $spfh, '<' . $file);
    binmode($spfh);
    $ctx->addfile($spfh);
    my $chksum = $ctx->hexdigest;
    close($spfh);
    undef $ctx;
    return $chksum;
}

sub irc_privmsg($$$) {
    my $irch = shift;
    my $target = shift;
    my $msg = shift;
    if ( defined($msg) and $msg ne '' ) {
        $irch->yield('privmsg', $target, $msg);
        log_db($target, 'privmsg', $msg);
    }
}

sub __bootup {
    umask 0;
    open(STDIN, '/dev/null') or die "Can't read /dev/null: $!";
    if ( $conf{'debug'} == 1 ) {
        open(STDOUT, ">>$conf{'debug_log'}") or die "Can't write to $conf{'stdout_log'}: $!";
    } else {
        open(STDOUT, ">/dev/null");
    }
    open(STDERR, ">>$conf{'error_log'}") or die "Can't write to $conf{'error_log'}: $!";
    defined(my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        log_error("PID of forked process is $pid.");
        open(my $pidfile, '>', $conf{'pidfile'}) or log_error("Couldn't open PID file $conf{'pidfile'}: $!");
        print { $pidfile } $pid;
        close($pidfile);
        exit;
    }
    setsid or die "Can't start a new session: $!";
    while(1) {
        use strict;
        use warnings;
        use sigtrap qw(handler _stop TERM);

        $chksum = filemd5($specialfile);

        require $specialfile;

        $dbh = db_connect;
        $irch = connect_irc;
        use sigtrap 'handler', sub {
            my $irc_connected = 2;
            my $irc_logged_in = 2;
            my $irc_channel = 3;
            my $db_connected = 2;
            my $db_execute = 2;
            log_debug("Testing daemon.");
            if ( $irch->connected() ) {
                log_debug("IRC client is connected.");
                $irc_connected = 1;
            }
            if ( $irch->logged_in() ) {
                log_debug("IRC client is logged in.");
                $irc_logged_in = 1;
            }
            my $topic = $irch->yield('channel_topic', $conf{'irc_chan'});
            if ( defined($topic) ) {
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
                log_debug("Test select succeeded.");
                $db_execute = 1;
            }
            open(my $fh, '>' . $conf{'testfile'});
            print {$fh} "irc_connected=$irc_connected\nirc_logged_in=$irc_logged_in\nirc_channel=$irc_channel\ndb_connected=$db_connected\ndb_execute=$db_execute";
            close($fh);
        }, 'USR2';
        use sigtrap 'handler', sub {
            my $reconnect = 0;
            log_debug("Reloading config file $configfile");
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
                    system('/bin/bash', '-c', "$conf{'initscript'} restart");
                }
            }
        
            my $chksum_new = filemd5($specialfile);

            log_debug("Checking for changes in special file. old MD5 = $chksum; new MD5 = $chksum_new");
            if ( "$chksum" ne "$chksum_new" ) {
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
}

# Returns:
#  0 - success
#  2 - error which needs to restart the bot
#  3 - bot isNn't connected to channel
sub __test {
    my $return = 0;
    open(my $pidfile, '<' . $conf{'pidfile'}) or ( log_error("Couldn't open PID file $conf{'pidfile'}: $!") and print "Couldn't open PID file $conf{'pidfile'}: $!" and $return = 1 );
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
            Rejoin_delay => 2,
        )
    );
    $irch->yield( register => 'all' );
    $irch->yield( connect => { } );
    return;
}


sub _stop {
    log_debug("Stopping daemon.");
    my $heap = $_[HEAP];
    my $irch = $heap->{irch};
    irc_privmsg($irch, $conf{'irc_chan'}, $conf{'irc_bye'});
    $irch->yield('shutdown', 'Good (UGT) Night');
    unlink($conf{'pidfile'});
    unlink($conf{'testfile'});
    exit 0;
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

sub irc_join {
    my ($sender, $who, $channel) = @_[SENDER, ARG0, ARG1];
    my $irch = $sender->get_heap();
    my ($nick, $host) = split /!/, $who;
    log_db($nick, 'join', "$nick ($host) has entered the channel");
    if ( defined($conf{'irc_warning'}) and $conf{'irc_warning'} ne '' ) {
        log_db($conf{'irc_nick'}, 'privmsg', $conf{'irc_warning'});
        irc_privmsg($irch, $nick, $conf{'irc_warning'});
    }
    if ( defined($conf{'irc_newcomer'}) and $conf{'irc_newcomer'} ne '' ) {
        log_db($conf{'irc_nick'}, 'privmsg', $conf{'irc_newcomer'});
        irc_privmsg($irch, $nick, $conf{'irc_newcomer'});
    }
}

sub irc_msg {
    my ($sender, $who, $rcpnick, $msg, $identified) = @_[SENDER, ARG0 .. ARG3];
    my $irch = $sender->get_heap();
    my $nick = ( split /!/, $who )[0];
    irc_privmsg($irch, $nick, "Thanks for talking to me but I'm just a humble ircbot of $conf{'irc_chan'}.");
    irc_privmsg($irch, $nick, "If you want to know more about me write in the channel 'dokubot help'.");
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

sub irc_public {
    my ($sender, $who, $channels, $msg, $identified) = @_[SENDER, ARG0 .. ARG3];
    my $irch = $sender->get_heap();
    my $nick = ( split /!/, $who )[0];
    log_db($nick, 'public', $msg);
    special($irch, \%conf, $msg, $nick);
    my $recipient = get_recipient($msg);
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
        $action = 'test';
    }
    if ($opts{'x'}) {
        $action = 'stop';
    }
} else {
    usage;
    exit 1;
}

defined($action) or $action = 'test';

%conf = loadconfig($configfile);

log_debug("Running action $action");
my $ret = eval '__' . $action;
exit $ret if defined($ret);

