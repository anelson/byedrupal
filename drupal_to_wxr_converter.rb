require 'ostruct'
require 'hpricot'

require File.dirname(__FILE__) + '/php_serialize'
require File.dirname(__FILE__) + '/xml_escape'


MIGRATED_CAT_NAME = "Migrated from Drupal"
MIGRATED_CAT_NICE_NAME = "migrated_from_drupal"

class DrupalToWxrConverter
    WORDPRESS_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

    def initialize(wxr_writer, drupal_reader, logger, options)
        @writer = wxr_writer
        @reader = drupal_reader
        @logger = logger
        @opts = options
        @node_errors = {}
        @next_post_id = 0
        @next_comment_id = 0
    end

    def run
        @writer.start_file
            @writer.write_rss_element("title", nil, @reader.title)
            @writer.write_rss_element("link", nil, @opts[:baseurl])
            @writer.write_rss_element("description", nil, @reader.description)
            @writer.write_rss_element("pubDate", nil, @reader.pub_date.httpdate)
            @writer.write_rss_element("generator", nil, "Adam Nelson's Drupal-to-WXR Migration Tool")
            if @opts[:lang]
                @writer.write_rss_element("language", nil, @opts[:lang])
            else
                @writer.write_rss_element("language", nil, @reader.default_locale)
            end
            @writer.write_wordpress_element("wxr_version", nil, "1.0")

            puts "Migrating categories and tags..."

            output_migrated_cat()            
            @reader.each_category do |cat|
                output_category(cat)
            end

            output_migrated_tag()         
            @reader.each_tag do |tag|
                output_tag(tag)
            end

            puts "Migrating #{@reader.num_nodes} Drupal nodes"
            @current_node_index = 0
            @reader.each_node do |node|
                output_node(node)
            end

            output_migrated_node()
        @writer.end_file
    end

    def node_errors
        @node_errors
    end

    private 

    def output_migrated_cat()
        cat = OpenStruct.new
        cat.name = MIGRATED_CAT_NICE_NAME
        cat.title = MIGRATED_CAT_NAME
        cat.description = "Nodes migrated from Drupal"
        output_category(cat)
    end

    def output_category(cat)
        #As a part of the boundless Wordpress shittiness, the resulting "XML" (and I use that term very loosely here)
        #must be all on one line if it's to be parsed correctly
        @writer.start_wordpress_element_nonewline("category", nil)  
            @writer.write_wordpress_element_nonewline("category_nicename", nil, cat.name)
            if cat.parent
                @writer.write_wordpress_element_nonewline("category_parent", nil, cat.parent.name)
            else
                @writer.write_wordpress_element_nonewline("category_parent", nil, "")
            end
            @writer.write_wordpress_cdata_element_nonewline("cat_name", nil, cat.title)
            if cat.description
                @writer.write_wordpress_cdata_element_nonewline("category_description", nil, cat.description)
            end
        @writer.end_wordpress_element_nonewline("category")
    end

    def output_migrated_tag()
        output_tag(MIGRATED_CAT_NICE_NAME)
    end

    def output_tag(tag)
        @writer.start_wordpress_element_nonewline("tag", nil)  
            @writer.write_wordpress_element_nonewline("tag_slug", nil, tag)
            @writer.write_wordpress_cdata_element_nonewline("tag_name", nil, tag)
        @writer.end_wordpress_element_nonewline("tag")  
    end

    def output_node_category(name, nicename)
        #Based on sample WXR files, it looks like categories get output twice, once in naked <category> elements
        #and again in <category> elements with domain="category" and the nicename specified in an attribute.
        #Upon review of the wordpress.php import code it seems only the <category> elements with no attributes
        #are used for the purposes of import.
        #Makes about as much sense as anything else in the Wordpress codebase.  Anyway
        @writer.write_rss_cdata_element("category", nil, name)
    end

    def output_node_tag(name)
        @writer.write_rss_cdata_element("category", {:domain => "tag"}, name)
    end

    def output_migrated_node
        # Insert a post with information about the migration
        post_timestamp = Time.new()
        @writer.start_rss_element("item", nil)
            relative_url = "wordpress-migration-powered-by-apocryph-org"
            abs_url = @opts[:baseurl] + "/" + relative_url
            @writer.write_rss_element("title", nil, "WordPress migration powered by Apocryph.org")
            @writer.write_rss_element("link", nil,  abs_url)
            @writer.write_rss_element("pubDate", nil, post_timestamp.httpdate)
            @writer.write_dublincore_element("creator", nil, 'admin')

            output_node_category(MIGRATED_CAT_NAME, MIGRATED_CAT_NICE_NAME)
            output_node_tag(MIGRATED_CAT_NICE_NAME)

            @writer.write_dublincore_element("guid", {"isPermalink" => "false"}, abs_url)
            @writer.write_rss_element("description", nil, "")

            @writer.write_rss_content_cdata_element("encoded", nil, 
                'The preceeding content was migrated from Drupal by <a href="http://apocryph.org/">Adam Nelson\'s</a> ByeDrupal tool.  Kindly leave this post in place to help increase awareness of this tool.')

            wordpress_post_id = get_next_post_id()
            @writer.write_wordpress_element("post_id", nil, wordpress_post_id)
            @writer.write_wordpress_element("post_date", nil, post_timestamp.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("post_date_gmt", nil, post_timestamp.utc.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("comment_status", nil, (@opts[:comments_open] ? "open" : "closed"))
            @writer.write_wordpress_element("ping_status", nil, (@opts[:pings_open] ? "open" : "closed"))
            @writer.write_wordpress_element("post_name", nil, relative_url)
            @writer.write_wordpress_element("status", nil, 'publish')
            @writer.write_wordpress_element("post_parent", nil, "0")
            @writer.write_wordpress_element("menu_order", nil, "0")
            @writer.write_wordpress_element("post_type", nil, 'post')
            @writer.write_wordpress_element("post_password", nil, "") 
        @writer.end_rss_element("item")
    end

    def output_node(node_obj)
        node = nil
        @current_node_index+=1

        @logger.do_node_conversion(node_obj.nid, node_obj.title, node_obj) do 
            node = @reader.decode_node(node_obj)

            #If the node's relative URL is the same as the node's canonical relative URL (which is of the form node/[nodeid],
            #then the wordpress version of the node's URL will be different, since WP doesn't support forward-slashes
            #in post names.  Fix it now
            if node.relative_url == node.canonical_relative_url
                node.relative_url.gsub!('/', '-')
            end

            node_abs_url = @opts[:baseurl] + "/" + node.relative_url
            node_canonical_abs_url = @opts[:baseurl] + "/" + node.canonical_relative_url

            @logger.log_info_html "Processing node <a href='#{node_abs_url}'>#{XmlEscape::escape(node.title)}</a>"

            #Pull all the URLs out of the content and make sure they're either external references
            #or links to Drupal content which actually exists
            verify_node_links(node, node_abs_url)
            
            @writer.start_rss_element("item", nil)
                @writer.write_rss_element("title", nil, node.title)
                @writer.write_rss_element("link", nil, node_abs_url)
                @writer.write_rss_element("pubDate", nil, node.created.httpdate)
                @writer.write_dublincore_element("creator", nil, node.creator)
    
                output_node_category(MIGRATED_CAT_NAME, MIGRATED_CAT_NICE_NAME)
                output_node_tag(MIGRATED_CAT_NICE_NAME)
                node.tags.each do |tag|
                    output_node_tag(tag)
                end
    
                @writer.write_dublincore_element("guid", {"isPermalink" => "false"}, node_canonical_abs_url)
                @writer.write_rss_element("description", nil, "")
    
                @writer.write_rss_content_cdata_element("encoded", nil, postprocess_node_content(node.content))

                @writer.write_drupal_element("drupal_node_id", nil, node.node_id)
                node.wordpress_post_id = get_next_post_id()
                @writer.write_wordpress_element("post_id", nil, node.wordpress_post_id)
                @writer.write_wordpress_element("post_date", nil, node.created.strftime(WORDPRESS_DATE_FORMAT))
                @writer.write_wordpress_element("post_date_gmt", nil, node.created.utc.strftime(WORDPRESS_DATE_FORMAT))
                @writer.write_wordpress_element("comment_status", nil, (@opts[:comments_open] ? "open" : "closed"))
                @writer.write_wordpress_element("ping_status", nil, (@opts[:pings_open] ? "open" : "closed"))
                @writer.write_wordpress_element("post_name", nil, node.relative_url)
                @writer.write_wordpress_element("status", nil, node.is_published ? "publish" : "draft")
                @writer.write_wordpress_element("post_parent", nil, "0")
                @writer.write_wordpress_element("menu_order", nil, "0")
                @writer.write_wordpress_element("post_type", nil, node.is_page ? "page" : "post")
                @writer.write_wordpress_element("post_password", nil, "")
                if node.is_page
                    @writer.start_wordpress_element("postmeta", nil)
                        @writer.write_wordpress_element("meta_key", nil, "_wp_page_template")
                        @writer.write_wordpress_element("meta_value", nil, "default")
                    @writer.end_wordpress_element("postmeta")
                end

                node.root_comments.each do |comment|
                    output_comment(node, comment, nil)
                end    
            @writer.end_rss_element("item")

            node.attachments.each do |attachment|
                output_attachment(node, attachment)
            end

            @logger.log_info_html "Successfully converted node <a href='#{node_abs_url}'>#{XmlEscape::escape(node.title)}</a>"

            num_warnings = @logger.message_count(ConversionLogger::LOG_LEVEL_WARNING)
            num_errors = @logger.message_count(ConversionLogger::LOG_LEVEL_ERROR)

            puts "Migrated node #{@current_node_index} of #{@reader.num_nodes}: #{num_warnings} warning(s), #{num_errors} error(s)"
        end
    end

    def output_comment(node, comment, reply_to_comment)
        @writer.start_wordpress_element("comment", nil)
            if comment.comment_id != DrupalReader::DISQUS_COMMENT_ID
                @writer.write_drupal_element("drupal_comment_id", nil, comment.comment_id)
            end
            @writer.write_wordpress_element("comment_id", nil, get_next_comment_id)
            @writer.write_wordpress_element("comment_author", nil, comment.poster_name)
            @writer.write_wordpress_element("comment_author_email", nil, comment.poster_email)
            @writer.write_wordpress_element("comment_author_url", nil, comment.poster_url)
            @writer.write_wordpress_element("comment_author_IP", nil, comment.hostname)
            @writer.write_wordpress_element("comment_date", nil, comment.timestamp.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("comment_date_gmt", nil, comment.timestamp.utc.strftime(WORDPRESS_DATE_FORMAT))
            content = comment.content
            if comment.title != nil && comment.title != DrupalReader::DISQUS_COMMENT_SUBJECT
                #WordPress doesn't have a field for comment subject, so inject it into the body
                content = "<strong>#{comment.title}</strong>\n\n" + (content || '')
            end
            @writer.write_wordpress_cdata_element("comment_content", nil, postprocess_node_content(content))
            @writer.write_wordpress_element("comment_approved", nil, comment.is_published ? "1" : "0")
            @writer.write_wordpress_element("comment_type", nil, "")
            @writer.write_wordpress_element("comment_parent", nil, (reply_to_comment == nil ? 0 : reply_to_comment.comment_id))
        @writer.end_wordpress_element("comment")

        comment.replies.each do |reply|
            output_comment(node, reply, comment)
        end
    end

    def output_attachment(node, attachment)
        @writer.start_rss_element("item", nil)
            attachment_abs_url = clean_url(@opts[:baseurl] + '/' + attachment.filepath)

            @writer.write_rss_element("title", nil, attachment.filename)
            @writer.write_rss_element("link", nil, attachment_abs_url)
            @writer.write_rss_element("pubDate", nil, node.created.httpdate)
            @writer.write_dublincore_element("creator", nil, node.creator)

            @writer.write_dublincore_element("guid", {"isPermalink" => "false"}, attachment_abs_url)
            @writer.write_rss_element("description", nil, attachment.description)

            @writer.write_rss_content_element("encoded", nil, "")

            @writer.write_drupal_element("drupal_attachment_id", nil, attachment.attachment_id)
            attachment.wordpress_post_id = get_next_post_id
            @writer.write_wordpress_element("post_id", nil, attachment.wordpress_post_id)
            @writer.write_wordpress_element("post_date", nil, node.created.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("post_date_gmt", nil, node.created.utc.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("comment_status", nil, (@opts[:comments_open] ? "open" : "closed"))
            @writer.write_wordpress_element("ping_status", nil, (@opts[:pings_open] ? "open" : "closed"))
            @writer.write_wordpress_element("post_name", nil, File.basename(attachment.filename, File.extname(attachment.filename)))
            @writer.write_wordpress_element("status", nil, "inherit")
            @writer.write_wordpress_element("post_parent", nil, node.wordpress_post_id)
            @writer.write_wordpress_element("menu_order", nil, "0")
            @writer.write_wordpress_element("post_type", nil, "attachment")
            @writer.write_wordpress_element("attachment_url", nil, attachment_abs_url)
        @writer.end_rss_element("item")
    end

    def verify_node_links(node, node_abs_url)
        #Find the A HREF and IMG SRC links and make sure they're either external links
        #or links to existing internal content.  If any are broken, warn
        doc = Hpricot(node.content)
        doc.search('//a[@href]') do |link| 
            link[:href] = verify_node_link(node, node_abs_url, link[:href])
        end

        doc.search('//img[@src]') do |img|
            img[:src] = verify_node_link(node, node_abs_url, img[:src])
        end

        node.content = doc.to_html
    end

    def verify_node_link(node, node_abs_url, link)
        link = clean_url(link)

        rewritten_link = link
        begin
            if @reader.is_internal_url(node_abs_url, link)
                internal_obj_abs_url = @reader.get_internal_object_url_from_url(node_abs_url, link)

                if internal_obj_abs_url == nil
                    @logger.log_warning "Link '#{link}' looks like an internal site link but it doesn't correspond to any Drupal content"
                else
                    #Convert this link to be relative to the node's absolute URL
                    rewritten_link = URI.parse(node_abs_url).route_to(internal_obj_abs_url)

                    #If this is a link by node id (of the form node/[nodeid], must replace
                    #the / with a - since the wordpress url will use a hyphen instead
                    if rewritten_link.path =~ /node\/(\d+)$/
                        rewritten_link.path = rewritten_link.path.sub(/node\/(\d+)$/, 'node-\1')
                    end

                    #If this is a link to a file attachment, rewrite the URL to reflect the wordpress equivalent
                    #of the file attachments path
                    if @reader.is_internal_url_file_attachment(rewritten_link.path)
                        rewritten_link = rewrite_drupal_attachment_url(node, rewritten_link)
                    end

                    rewritten_link = rewritten_link.to_s()
                end
            end
        rescue URI::InvalidURIError
            @logger.log_warning "Link '#{link}' is not a valid URL"
        end

        if rewritten_link != link
            @logger.log_trace "Changed link to '#{link}' to '#{rewritten_link}'"
        end
                
        rewritten_link
    end

    def clean_url(link)
        link.gsub(' ', '%20')
    end

    def rewrite_drupal_attachment_url(node, attachment_url)
        #Drupal attachment URLs default to "files/[filename]" though that can be changed
        #I assume the filename portion of the URL is all that matters, and apply the wordpress upload path
        #URL prefix to that name, replacing %year% and %month% placeholders with the year and month of the post
        filename = File.basename(attachment_url.path)
        wp_path = @opts[:wp_uploads_url] + '/' + filename
        wp_path.gsub!('%year%', node.created.strftime('%Y'))
        wp_path.gsub!('%month%', node.created.strftime('%m'))

        wp_path
    end

    def get_next_post_id
        @next_post_id += 1
        @next_post_id
    end

    def get_next_comment_id
        @next_comment_id += 1
        @next_comment_id
    end

    def postprocess_node_content(content_in)
        #It seems WordPress expects the raw 'HTML' content of its posts to use blank lines in place of <p> marks
        #The Drupal content, after it's post-processed by textile or markdown, uses <p> elements.  Just strip all the <P>
        #elements
        #content_in.sub(/<\/?p>/i, '')
        return nil unless content_in != nil
        content_in.gsub(/<\/?p>/i, '')
    end
end
