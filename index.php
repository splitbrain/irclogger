<?php

require("func.php");
$conf = loadconfig('irclogger.config.php');


header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
 "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
<head>
    <title>IRC channel log</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <link rel="stylesheet" media="all" type="text/css" href="style.css" />
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
    $res = mysql_query($sql,$dbh);
    $row = mysql_fetch_array($res, MYSQL_ASSOC);
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

if($sql) $res = mysql_query($sql,$dbh);

if($date){
    echo '<form action="index.php">';
    echo '<h1>Log for <input type="text" name="d" value="'.htmlspecialchars($date).'" /></h1>';
    echo '</form>';
}elseif($sql && $_REQUEST['u']){
    echo '<h1>Log since last login of '.htmlspecialchars($_REQUEST['u']).'</h1>';
}elseif($sql && $_REQUEST['s']){
    echo '<h1>Matching lines for '.htmlspecialchars($_REQUEST['s']).'</h1>';
    echo '<p>Click the timestamp to see the line in context.</p>';
}

echo '<ul id="log">';
if($sql) while($row = mysql_fetch_array($res, MYSQL_ASSOC)){
    echo '<li>';
    echo '<a id="msg'.$row['id'].'" href="index.php?d='.$row['d'].'#msg'.$row['id'].'" class="time">';
    echo '['.$row['t'].']';
    echo '</a>';
    if($row['type'] == 'public'){
        echo '<b style="color:#'.substr(md5($row['user']),0,6).'">'.htmlspecialchars($row['user']).'</b><span class="user">';
    }else{
        echo '<b>*</b><span class="server">';
    }
    $msg = htmlspecialchars(  $row['msg']);
    $msg = preg_replace_callback('/((https?|ftp):\/\/[\w-?&;#~=\.\/\@%:]+[\w\/])/ui',
                                 'format_link',$msg);

    if(substr($msg,0,3) == '/me'){
        $msg = '<strong>'.htmlspecialchars($row['user']).substr($msg,3).'</strong>';
    }
    echo $msg;
    echo '</span>';
    echo '</li>';

}
echo '</ul>';

$sql = "SELECT DISTINCT DATE(dt) as d, DAY(dt) as day
          FROM messages
         WHERE dt > DATE_SUB(NOW(), INTERVAL 30 DAY)
      ORDER BY dt";
$res = mysql_query($sql,$dbh);

echo '<div class="archive">Last 30 days: ';
while($row = mysql_fetch_array($res, MYSQL_ASSOC)){
    echo '<a href="index.php?d='.$row['d'].'">'.$row['day'].'</a> ';
}
echo '</div>';

?>

<div class="footer"><div>
<ul>
    <li><a href="index.php?d=<?php echo date('Y-m-d')?>">Today's log</a></li>
    <li><a href="index.php?d=<?php echo date('Y-m-d',time()-(60*60*24))?>">Yesterday's log</a></li>
</ul>
<ul>
    <li>What happened since your last login?<br />
        <form action="index.php"><input name="u" /></form>
        <small>(Give your nick name and hit enter)</small></li>
    <li>Search:<br />
        <form action="index.php"><input name="s" /></form>
        <small>(Give search terms and hit enter)</small></li>
</ul>
<ul>
    <li style="width: 25em;">Powered by a homemade, experimental IRC logger written in Perl, PHP and MySQL.<br />
    A <a href="http://www.splitbrain.org">splitbrain.org</a> service.</li>
</ul>
</div></div>

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
