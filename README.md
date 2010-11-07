# byedrupal #

This is a quick and dirty Ruby script which I wrote to migrate my apocryph.org blog from Drupal to Wordpress.

It works by reading the Drupal database directly, and generating a WordPress .wxr file suitable for importing using the WordPress import tool.

It's pretty specific to my Drupal setup at the time, but it does handle conversion from MarkDown and Textile to HTML, attachments, and other tricky issues
that I ran into but forget about now.
