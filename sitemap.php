<?php

require('func.php');
$conf = loadconfig('irclogger.config.php');
$dbh = getdbhandle($conf);

$sql = "SELECT DISTINCT DATE(dt) as d
          FROM messages
      ORDER BY dt DESC";
$res = mysql_query($sql,$dbh);

$first = true;

header("Content-Type: text/xml");
echo '<?xml version="1.0" encoding="UTF-8"?>'."\n";
echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'."\n";
while($row = mysql_fetch_array($res, MYSQL_ASSOC)){
    echo "<url>\n";
    echo "   <loc>".$conf['baseurl'].'?d='.$row['d']."</loc>\n";
    echo "   <lastmod>".$row['d']."</lastmod>\n";
    if($first){
        echo "   <changefreq>hourly</changefreq>\n";
        $first = false;
    }else{
        echo "   <changefreq>never</changefreq>\n";
    }
    echo "</url>\n";
}
echo "</urlset>\n"; 

