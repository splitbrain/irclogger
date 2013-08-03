DROP TABLE IF EXISTS `messages`;
CREATE TABLE `messages` (
  `id` bigint(20) NOT NULL auto_increment,
  `dt` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `user` varchar(255) collate utf8_unicode_ci NOT NULL default '',
  `type` varchar(32) collate utf8_unicode_ci NOT NULL default '',
  `msg` text collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`id`),
  KEY `user` (`user`),
  FULLTEXT KEY `msg` (`msg`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
DROP TABLE IF EXISTS `msgstore`;
CREATE TABLE `msgstore` (
  `id` bigint(20) NOT NULL auto_increment,
  `dt` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `sender` varchar(255) collate utf8_unicode_ci NOT NULL default '',
  `recipient` varchar(255) collate utf8_unicode_ci NOT NULL default '',
  `msg` text collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
