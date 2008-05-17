require 'ostruct'
require 'hpricot'

require File.dirname(__FILE__) + '/php_serialize'
require File.dirname(__FILE__) + '/xml_escape'



class DrupalToWxrConverter
    WORDPRESS_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

    def initialize(wxr_writer, drupal_reader, logger, options)
        @writer = wxr_writer
        @reader = drupal_reader
        @logger = logger
        @opts = options
        @node_errors = {}
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

            output_migrated_cat()            
            @reader.each_category do |cat|
                output_category(cat)
            end

            output_migrated_tag()         
            @reader.each_tag do |tag|
                output_tag(tag)
            end
    
            @reader.each_node do |node|
                output_node(node)
            end
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
        @writer.start_wordpress_element("category", nil)  
            @writer.write_wordpress_element("category_nicename", nil, cat.name)
            if cat.parent
                @writer.write_wordpress_element("category_parent", nil, cat.parent.name)
            else
                @writer.write_wordpress_element("category_parent", nil, "")
            end
            @writer.write_wordpress_element("cat_name", nil, cat.title)
            if cat.description
                @writer.write_wordpress_element("category_description", nil, cat.description)
            end
        @writer.end_wordpress_element("category")
    end

    def output_migrated_tag()
        output_tag(MIGRATED_CAT_NICE_NAME)
    end

    def output_tag(tag)
        @writer.start_wordpress_element("tag", nil)  
            @writer.write_wordpress_element("tag_slug", nil, tag)
            @writer.write_wordpress_element("tag_name", nil, tag)
        @writer.end_wordpress_element("tag")  
    end

    def output_node(node_obj)
        node = nil
        @logger.do_node_conversion(node_obj.nid, node_obj.title, node_obj) do 
            node = @reader.decode_node(node_obj)
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
    
                node.tags.each do |tag|
                    @writer.write_rss_element("category", {:domain => "tag"}, tag)
                end
    
                @writer.write_dublincore_element("guid", {"isPermalink" => "false"}, node_canonical_abs_url)
                @writer.write_rss_element("description", nil, "")
    
                @writer.start_rss_content_element("encoded", nil)
                    @writer.write_cdata_value(node.content)
                @writer.end_rss_content_element("encoded")

                @writer.write_wordpress_element("post_id", nil, node.node_id)
                @writer.write_wordpress_element("post_date", nil, node.created.strftime(WORDPRESS_DATE_FORMAT))
                @writer.write_wordpress_element("post_date_gmt", nil, node.created.utc.strftime(WORDPRESS_DATE_FORMAT))
                @writer.write_wordpress_element("comment_status", nil, (@opts[:comments_open] ? "open" : "closed"))
                @writer.write_wordpress_element("ping_status", nil, (@opts[:pings_open] ? "open" : "closed"))
                @writer.write_wordpress_element("post_name", nil, node.relative_url)
                @writer.write_wordpress_element("status", nil, node.is_published ? "publish" : "draft")
                @writer.write_wordpress_element("post_parent", nil, "0")
                @writer.write_wordpress_element("menu_order", nil, "0")
                @writer.write_wordpress_element("post_type", nil, node.is_page ? "page" : "blog")
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
        end
    end

    def output_comment(node, comment, reply_to_comment)
        @writer.start_wordpress_element("comment", nil)
            @writer.write_wordpress_element("comment_id", nil, comment.comment_id)
            @writer.write_wordpress_element("comment_author", nil, comment.poster_name)
            @writer.write_wordpress_element("comment_author_email", nil, comment.poster_email)
            @writer.write_wordpress_element("comment_author_url", nil, comment.poster_url)
            @writer.write_wordpress_element("comment_author_IP", nil, comment.hostname)
            @writer.write_wordpress_element("comment_date", nil, comment.timestamp.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("comment_date_gmt", nil, comment.timestamp.utc.strftime(WORDPRESS_DATE_FORMAT))
            @writer.start_wordpress_element("comment_content", nil)
                content = comment.content
                if comment.title.length > 0
                    #WordPress doesn't have a field for comment subject, so inject it into the body
                    content = "<p>Subject: #{comment.title}</p>\n" + content
                end
                @writer.write_cdata_value(content)
            @writer.end_wordpress_element("comment_content")
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
            attachment_abs_url = @opts[:baseurl] + '/' + attachment.filepath

            @writer.write_rss_element("title", nil, attachment.filename)
            @writer.write_rss_element("link", nil, attachment_abs_url)
            @writer.write_rss_element("pubDate", nil, node.created.httpdate)
            @writer.write_dublincore_element("creator", nil, node.creator)

            @writer.write_dublincore_element("guid", {"isPermalink" => "false"}, attachment_abs_url)
            @writer.write_rss_element("description", nil, attachment.description)

            @writer.start_rss_content_element("encoded", nil)
                @writer.write_cdata_value("")
            @writer.end_rss_content_element("encoded")

            # NB: attachment IDs and node IDs are independent, so using both for the post ID could lead to collissions
            # Thus, add a huge number to the attachment ID to keep it unique
            @writer.write_wordpress_element("post_id", nil, 2000000000 + attachment.attachment_id)
            @writer.write_wordpress_element("post_date", nil, node.created.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("post_date_gmt", nil, node.created.utc.strftime(WORDPRESS_DATE_FORMAT))
            @writer.write_wordpress_element("comment_status", nil, (@opts[:comments_open] ? "open" : "closed"))
            @writer.write_wordpress_element("ping_status", nil, (@opts[:pings_open] ? "open" : "closed"))
            @writer.write_wordpress_element("post_name", nil, File.basename(attachment.filename, File.extname(attachment.filename)))
            @writer.write_wordpress_element("status", nil, "inherit")
            @writer.write_wordpress_element("post_parent", nil, node.node_id)
            @writer.write_wordpress_element("menu_order", nil, "0")
            @writer.write_wordpress_element("post_type", nil, "attachment")
            @writer.start_wordpress_element("postmeta", nil)
                attachment_local_file_path = @opts[:drupal_files_path] + '/' + attachment.filepath

                @writer.write_wordpress_element("meta_key", nil, "_wp_attached_file")
                @writer.write_wordpress_element("meta_value", nil, attachment_local_file_path)

                @writer.write_wordpress_element("meta_key", nil, "_wp_attachment_metadata")
                # The attachment metadata is a serialized PHP array with some name/value pairs.  
                # Images include dimension metadata in the NVP as well as the filename of the thumbnail version
                # I'm hoping I don't have to do that here.  I'll just include the repetition of the file path
                metadata = {"file" => attachment_local_file_path}
                @writer.write_wordpress_element("meta_value", nil, PHP.serialize(metadata))
            @writer.end_wordpress_element("postmeta")
        @writer.end_rss_element("item")
    end

    def verify_node_links(node, node_abs_url)
        #Find the A HREF and IMG SRC links and make sure they're either external links
        #or links to existing internal content.  If any are broken, warn
        doc = Hpricot(node.content)
        doc.search('//a[@href]') do |link| 
            verify_node_link(node, node_abs_url, link.attributes['href'])
        end

        doc.search('//img[@src]') do |img|
            verify_node_link(node, node_abs_url, img.attributes['src'])
        end
    end

    def verify_node_link(node, node_abs_url, link)
        begin
            if @reader.is_internal_url(node_abs_url, link) &&
               !@reader.does_internal_url_exist(node_abs_url, link)
               @logger.log_warning "Link '#{link}' looks like an internal site link but it doesn't correspond to any Drupal content"
            end
        rescue URI::InvalidURIError
            @logger.log_warning "Link '#{link}' is not a valid URL"
        end
    end
end
