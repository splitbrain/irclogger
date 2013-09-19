# do your own actions here
#
# Params are Net::IRC, msg, user
use strict;
use warnings;

sub special($$$$) {
    my $irc  = shift;
    my $conf = shift;
    my $msg  = shift;
    my $nick = shift;

    if (my(@tickets) = $msg =~ m/\bFS#(\d\d+)\b/g) {
        privmsg_irc($irc, $conf->{'irc_chan'}, "See bugreport $_ at http://bugs.dokuwiki.org/index.php?do=details&task_id=$_") for @tickets;
    } elsif (my(@prs) = $msg =~ m/\bPR#(\d\d+)\b/g) {
        privmsg_irc($irc, $conf->{'irc_chan'}, "See pull request $_ at https://github.com/splitbrain/dokuwiki/pull/$_") for @prs;
    } elsif (my(@pages) = $msg =~ m/(?:^|\s)(:?[-\w_#]*:[-\w_#]+(?::[-\w_#]+)*)(?:\s|$)/g) {
        my @out;
        for my $id (@pages) {
            my @link = split(/#/, $id);
            $id = $link[0];
            if (defined($link[1])) {
            my $anchor;
                $anchor = lc($link[1]);
            }
            $id =~ s/^://;
            (my $p = lc($id)) =~ s#:#/#g;

            # page must exist
            next unless -e "/var/www/wiki/htdocs/data/pages/$p.txt";
            if ( defined($anchor) and $anchor ne '' ) {
                push(@out, 'http://www.dokuwiki.org/'.$id."#".$anchor);
            } else {
                push(@out, 'http://www.dokuwiki.org/'.$id);
            }
        }

        privmsg_irc($irc, $conf->{'irc_chan'}, join(', ', @out)) if @out;

    }elsif($msg =~ m/\bUGT\b/){
        privmsg_irc($irc, $conf->{'irc_chan'}, 'UGT - Universal Greeting Time http://www.total-knowledge.com/~ilya/mips/ugt.html'.$1);
    }elsif(length($msg) < 50 and  $msg =~ m/((have|got|ask).*?(question))|((can|may) I ask )/i){
        privmsg_irc($irc, $conf->{'irc_chan'}, $nick.', just ask your question and stay in the channel for a while.');
    }elsif($msg =~ m/\bgame\b/i){
        privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, you just lost the game!");
    }elsif($msg =~ m/\bfoobar/i){
        privmsg_irc($irc, $conf->{'irc_chan'}, "Hi, I'm currently at the bar drinking some foo. What do you want?");
    }elsif($msg =~ m/\Q$conf->{'irc_nick'}\E/){
        if($msg =~ m/\b(thanks?|thx)\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, I'm just a humble bot, don't thank me.");
        }elsif($msg =~ m/\b(hug|love|kiss)/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, I'm just a stupid bot, but your kindness makes me wish to be human.");
        }elsif($msg =~ m/\bcoffee\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, here's the hot, steamy coffee you ordered.");
        }elsif($msg =~ m/\btea\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, your tea is ready my dear.");
        }elsif($msg =~ m/\bjolt\b/i){
            if($nick eq 'foosel'){
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, here is your ice cold Jolt, my lady.");
            }else{
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, here is your ice cold Jolt. May I recommend to drink it quick, before foosel grabs it?");
            }
        }elsif($msg =~ m/\bbeer\b/i){
            if($nick eq 'chimeric'){
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, have a cool, refreshing Augustiner beer. Prost!");
            }elsif($nick eq 'selfthinker'){
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, have a cool, refreshing ginger beer. Cheers, mate!");
            }else{
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, have a cool, refreshing beer, you've earned it.");
            }
        }elsif($msg =~ m/\bwine\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, please enjoy your glass of wine.");
        }elsif($msg =~ m/\b(wh?isk(ey|y))\b/i){
            if($nick eq 'Chris--S'){
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, here is your glass of Scotch, please enjoy the taste of your homeland.");
            }else{
                privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, here is your glass of fine $1.");
            }
        }elsif($msg =~ m/\bcookies?\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, enjoy your cookie. I will take care of the crumbs.");
        }elsif($msg =~ m/\bcake\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "$nick, the cake is a lie!");
        }elsif($msg =~ m/\b(poke|tickle)s?\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "*giggle* $nick, please stop this. :-)");
        }elsif($msg =~ m/\bzimbot\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "*blush* zimbot is kinda cute.");
        }elsif($msg =~ m/\b(hi|hello|heyas|hey|good morning|good evening|welcome|wb)\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "Hello $nick, I'm just a humble bot but I'll try my best to serve you.");
        }elsif($msg =~ m/\bhelp\b/i){
            privmsg_irc($irc, $conf->{'irc_chan'}, "Hi, I'm the humble bot of $conf->{'irc_chan'}.");
        }
    }
}

1;
# vim:et:ts=4
