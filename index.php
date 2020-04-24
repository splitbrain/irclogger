<?php
error_reporting(E_ALL & ~E_NOTICE);

require("func.php");
$conf = loadconfig('irclog.config.php');


header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="en" dir="ltr">
<head>
    <meta charset="utf-8" />
    <title>IRC log of <?php echo $conf['irc_chan'] ?> @ <?php echo $conf['irc_host']?></title>
    <link rel="stylesheet" media="all" type="text/css" href="style.css?v=2" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
</head>
<body>
<?php
$dbh = getdbhandle($conf);

if($_REQUEST['s']){
    $sql = "SELECT id, DATE(dt) as d, TIME(dt) as t, user, type, msg
              FROM messages
             WHERE MATCH (msg)
           AGAINST ('".addslashes($_REQUEST['s'])."')
          ORDER BY dt DESC, id DESC
             LIMIT 1000";
}elseif($_REQUEST['u']){
    $sql = "SELECT dt
              FROM messages
             WHERE user = '".addslashes($_REQUEST['u'])."'
          ORDER BY dt DESC, id DESC
             LIMIT 1";
    $res = mysqli_query($dbh,$sql);
    $row = mysqli_fetch_array($res, MYSQLI_ASSOC);
    if($row['dt']){
        $sql = "SELECT id, DATE(dt) as d, TIME(dt) as t, user, type, msg
              FROM messages
             WHERE dt >= '".addslashes($row['dt'])."'
          ORDER BY dt, id
         LIMIT 1000";
    }else{
        echo 'Could not find any logs for user '.htmlspecialchars($_REQUEST['u']);
        $sql = '';
    }
}else{
    if($_REQUEST['d']){
        $date = $_REQUEST['d'];
    }else{
        $date = date('Y-m-d');
    }

    $sql = "SELECT id, DATE(dt) as d, TIME(dt) as t, user, type, msg
              FROM messages
             WHERE DATE(dt) = DATE('".addslashes($date)."')
          ORDER BY dt, id";
}

if($sql) $res = mysqli_query($dbh,$sql);

echo '<h1>IRC log of '.$conf['irc_chan'].' @ '.$conf['irc_host'].'</h1>';
if($date){
    echo '<h2>For <em title="'.htmlspecialchars($date).'">'.date('l, j F Y', strtotime(htmlspecialchars($date))).'</em></h2>';
}elseif($sql && $_REQUEST['u']){
    echo '<h2>Since last login of <em>'.htmlspecialchars($_REQUEST['u']).'</em></h2>';
}elseif($sql && $_REQUEST['s']){
    echo '<h2>Matching lines for <em>'.htmlspecialchars($_REQUEST['s']).'</em></h2>';
    echo '<p>Click the timestamp to see the line in context.</p>';
}
echo '<a href="#nav" class="skip">skip to navigation</a>';

// content *******************************************
echo '<ol id="log">';
if($sql) while($row = mysqli_fetch_array($res, MYSQLI_ASSOC)){
    echo '<li id="msg'.$row['id'].'" class="'.$row['type'].'">';
    echo '<a href="index.php?d='.$row['d'].'#msg'.$row['id'].'" class="time" title="'.$row['d'].'">';
    // give screenreaders a hint early enough which line includes a real message
    if($row['type'] == 'public') echo '<span class="a11y">message at </span>';
    echo '<time datetime="'.$row['d'].'T'.$row['t'].'">'.$row['t'].'</time>';
    echo '</a>';
    echo '<dl>';
    if($row['type'] == 'public'){
        echo '<dt style="color:#'.substr(md5($row['user']),0,6).'" class="user">'.htmlspecialchars($row['user']).'</dt>';
    }else{
        echo '<dt class="server">'.$row['type'].'</dt>';
    }
    $msg = htmlspecialchars(  $row['msg']);
    $msg = preg_replace_callback('/((https?|ftp):\/\/[\w\-?&;#~=\.\/\@%:]+[\w\/])/ui',
                                 'format_link',$msg);

    echo '<dd>';
    if(substr($msg,0,3) == '/me'){
        $msg = '<strong>'.htmlspecialchars($row['user']).substr($msg,3).'</strong>';
    }
    echo $msg;
    echo '</dd>';
    echo '</dl>';
    echo '</li>';

}
echo '</ol>';

// nav *******************************************
$sql = "SELECT DISTINCT DATE(dt) as d, DAY(dt) as day
          FROM messages
         WHERE dt > DATE_SUB(NOW(), INTERVAL 30 DAY)
      ORDER BY dt";
$res = mysqli_query($dbh,$sql);

echo '<div id="nav">';
echo '<h2 class="a11y">Navigation</h2>';
echo '<h3>Last 30 days</h3>';
echo '<ul class="archive">';
while($row = mysqli_fetch_array($res, MYSQLI_ASSOC)){
    echo '<li><a href="index.php?d='.$row['d'].'" title="'.$row['d'].'">'.$row['day'].'</a></li>';
}
?>

    <li class="today"><a href="index.php?d=<?php echo date('Y-m-d')?>" title="<?php echo date('Y-m-d')?>">Today's log</a></li>
    <li class="yesterday"><a href="index.php?d=<?php echo date('Y-m-d',time()-(60*60*24))?>" title="<?php echo date('Y-m-d',time()-(60*60*24))?>">Yesterday's log</a></li>
</ul>

<h3>Filters</h3>
<p class="hint">Enter one of the filters and hit return.</p>
<ul class="filters">
    <li>
        <form action="index.php">
            <label for="d">Date</label>
            <input type="date" name="d" id="d" value="<?php echo htmlspecialchars($date) ?>" />
            <small>Format: <abbr title="four digit year, dash, two digit month, dash, two digit day">yyyy-mm-dd</abbr></small>
        </form>
    </li>
    <li>
        <form action="index.php">
            <label for="u">Nick name</label>
            <input type="text" name="u" id="u" value="" />
            <small>What happened since your last login?</small>
        </form>
    </li>
    <li>
        <form action="index.php">
            <label for="s">Search</label>
            <input type="search" name="s" id="s" value="" />
            <small>Search for one or more words</small>
        </form>
    </li>
</ul>

</div>


<footer>
    <p>Powered by a homemade, experimental IRC logger written in Perl, PHP and MySQL.<br />
    A <a href="http://www.splitbrain.org">splitbrain.org</a> service.</p>
</footer>

<?php
    include('/var/www/wiki/htdocs/lib/tpl/dokuwiki/dwtb.html');
?>

</body>
</html>
<?php

/**
 * Callback to autolink a URL (with shortening)
 */
function format_link($match){
    $url = $match[1];
    $url = str_replace("\\\\'","'",$url);
    $link = '<a href="'.$url.'" rel="nofollow">'.$url.'</a>';
    return $link;
}


?>
