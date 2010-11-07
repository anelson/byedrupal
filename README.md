# byedrupal #

This is a quick and dirty Ruby script which I wrote to migrate my apocryph.org blog from Drupal to Wordpress.

It works by reading the Drupal database directly, and generating a WordPress .wxr file suitable for importing using the WordPress import tool.

It's pretty specific to my Drupal setup at the time, but it does handle conversion from MarkDown and Textile to HTML, attachments, migrating Disqus comments to WordPress commands,
and other tricky issues that I ran into but forget about now.

Here's the command line I used way back when: 

     ruby -Ku drupal2wxr.rb 
         --dbhost <drupal MySQL database hostname> 
	 --dbusername <drupal MySQL username> 
	 --dbpassword <drupal MySQL password> 
	 --dbname <drupal MySQL database name> 
	 --baseurl <base URL of Drupal site, e.g. http://apocryph.org> 
	 --disqus-comments-file <path to exported Disqus comments file> 
	 --debug <Output debug info>
	 --debug <Output more debug info>
	 

