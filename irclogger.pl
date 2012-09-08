#!/usr/bin/perl

$configfile = 'irclogger.config.php';

require "irclogger.special.pl";

# --- no changes needed below ---
$|=1;

use Net::IRC;
use DBI;
use Data::Dumper;
$connected = 0;

sub loadconfig($){
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


sub on_connect {
    my $self = shift;

    return if($connected);

    print "Joining channel $conf{'irc_chan'}...";
    $self->join($conf{'irc_chan'});
    print " done\n";

#    $self->privmsg($conf{'irc_chan'}, sprintf($conf{'hello'}));
    $connected = 1;
}

sub on_error {
    my $self  = shift;
    my $event = shift;

    print "ERROR: ".$event->{'args'};
    exit;
}

# disconnect handler
sub on_disconnect {
    my ($self, $event) = @_;

    $connected = 0;

    # try to reconnect if configured to do so
    if ($conf{'irc_reconnect'}) {
        print "Disconnected from ", $event->from(), " (", ($event->args())[0], "). Attempting to reconnect in ", $conf{'irc_reconnect'}, " seconds...\n";
		sleep($conf{'irc_reconnect'});
        $self->connect();
        return;
    }

    # otherwise just exit
    exit;
}

sub on_msg {
    my $self  = shift;
    my $event = shift;

    # never talk to our self
    return if ($event->{nick} eq $conf{irc_nick});

    # pretty print non-chat messages
    my $msg = $event->{args}[0];
    if($event->{type} eq 'nick'){
        $msg = sprintf("%s is now known as %s",
                       $event->{nick},
                       $event->{args}[0]);
    }elsif($event->{type} eq 'part'){
        $msg = sprintf("%s (%s) has left the channel (%s)",
                       $event->{nick},
                       $event->{userhost},
                       $event->{args}[0]);
    }elsif($event->{type} eq 'quit'){
        $msg = sprintf("%s (%s) has quit (%s)",
                       $event->{nick},
                       $event->{userhost},
                       $event->{args}[0]);
    }elsif($event->{type} eq 'join'){
        $msg = sprintf("%s (%s) entered the channel",
                       $event->{nick},
                       $event->{userhost});
        # warn newcoming users personally:
        $self->privmsg($event->{nick},sprintf($conf{'warning'},$event->{nick}));
    }elsif($event->{type} eq 'caction'){
        $event->{type} = 'public';
        $msg = '/me '.$msg;
    }

    print join(' ',time(),'<'.$event->{nick}.'>','['.$event->{type}.']:',$msg,"\n");

    $dbh->do("INSERT INTO messages (user,type,msg) VALUES (?,?,?)",undef,
             $event->{nick},$event->{type},$msg);
    special($self,$msg,$event->{nick});
}

%conf = loadconfig($configfile);

$dbh = DBI->connect("DBI:mysql:database=$conf{db_name};host=$conf{db_host}",
                      $conf{db_user}, $conf{db_pass}) || die "failed to open DB connection";
$dbh->{mysql_auto_reconnect} = 1;

$irc = new Net::IRC;

$conn = $irc->newconn(Nick    => $conf{irc_nick},
                      Server  => $conf{irc_host},
                      Port    => $conf{irc_port},
                      Ircname => $conf{irc_name},
                      Password=> $conf{irc_pass});
$conn->add_global_handler('376',\&on_connect);
$conn->add_global_handler('422',\&on_connect);
$conn->add_global_handler('error',\&on_error);
$conn->add_global_handler('disconnect',\&on_disconnect);

$conn->add_handler('msg', \&on_msg);
$conn->add_handler('public', \&on_msg);
$conn->add_handler('join', \&on_msg);
$conn->add_handler('part', \&on_msg);
$conn->add_handler('nick', \&on_msg);
$conn->add_handler('quit', \&on_msg);
$conn->add_handler('caction', \&on_msg);


print "Opening connection to $conf{'irc_host'}:$conf{'irc_port'}...\n";
$irc->start;

