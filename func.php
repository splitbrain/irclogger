<?php

loadconfig($file){
    $conf = array();
    $lines = @file( $file );
    if ( !$lines ) return $conf;

    foreach ( $lines as $line ) {
        //ignore comments
        $line = preg_replace('/^#.*$/','',$line);
        $line = trim($line);
        if(empty($line)) continue;
        $line = preg_split('/\s*=\s*/',$line,2);
            $conf[$line[0]] = $line[1];
        }
    }
    return $conf;
}

getdbhandle($conf){
    $dbh = mysql_connect($conf['db_host'],$conf['db_user'],$conf['db_pass']) or
            die("failed to connect to database");
    mysql_select_db($conf['db_name'],$dbh) or die('Could not select database');
    mysql_query("SET NAMES 'utf8'");
    return $dbh;
}
