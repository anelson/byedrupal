# Connects to a Drupal 6 MySQL database and extracts all nodes into a data structure for use 
# migrating to another platform
require 'ostruct'
require 'time'
require 'uri'
require 'cgi'
require 'drupal_model'

require 'redcloth' # required only to convert drupal content in textile format
require 'bluecloth' # required only to convert drupal content in markdown format
#require 'rubypants' # as above but for smartypants

require 'rexml/document'


class DrupalReader
    DISQUS_COMMENT_ID = -1
    DISQUS_COMMENT_SUBJECT = "Migrated Disqus comment"

    def initialize(dbhost, dbusername, dbpassword, dbname, baseurl, disqus_comments, logger)
        DrupalModel::Config.setup(
            {:adapter => 'mysql',
             :host => dbhost,
             :username => dbusername,
             :password => dbpassword,
             :database => dbname})

        @logger = logger

        #Need the trailing slash at the end of the URL since URL aliases within Drupal
        #don't include a leading slash
        @baseurl = URI.parse(baseurl + '/')


        #Pre-compute the list of URL aliases so we don't hit the database with each node
        #While we're at it, precompute the reverse: a hash of URL aliases as the key, and the source URL
        #as the value
        @url_aliases = {}
        @url_alias_sources = {}
        DrupalModel::UrlAlias.find(:all).each do |url_alias|
            @url_aliases[url_alias.src] = CGI.escape(url_alias.dst)
            @url_alias_sources[url_alias.dst] = CGI.escape(url_alias.src)
        end

        #Do the same for users to save a UID lookup
        @users = {}
        DrupalModel::User.find(:all).each do |user|
            @users[user.uid] = user.name
        end

        #Ditto for file objects by file path
        @files = {}
        DrupalModel::File.find(:all).each do |file|
            @files[file.filepath] = file
        end

        #Cache the tags list as well
        @tags = {}
        tags_vocab = find_all_tags
        if tags_vocab
            tags_vocab.term_data.each do |tag|
                @tags[tag.tid] = tag.name
            end
        end

        #Pre-fetch the site node count
        @num_nodes = DrupalModel::Node.count(:all)

        #If a disqus comments file was specified, load the comments in advance
        unless disqus_comments == nil
            File.open(disqus_comments, "r") do |file|
                @disqus_comments = load_disqus_comments(file)
            end
        end
        @disqus_comments ||= nil

        #Look through the filters installed on the system.  If any filters associated with the markdown
        #or textile modules are encountered, preserve the format IDs the filters are associated with so we'll
        #know to pre-process the content with the appropriate filter
        @markdown_formats = []
        @textile_formats = []
        DrupalModel::Filter.find(:all).each do |filter|
            if filter.module == "textile"
                @logger.log_debug "Found textile format '#{filter.format}'"
                @textile_formats << filter.format
            elsif filter.module == "marksmarty"
                @logger.log_debug "Found markdown format '#{filter.format}'"
                @markdown_formats << filter.format
            end
        end
    end

    def each_node(&block)
        DrupalModel::Node.find(:all).each do |node_obj|
            block.call(node_obj)
        end     
    end

    def decode_node(node_obj)
        node = OpenStruct.new
        node.node_id = node_obj.nid
        node.title = node_obj.title
        node.canonical_relative_url = compute_canonical_node_url(node_obj)
        node.relative_url = compute_alias_url(node.canonical_relative_url)
        node.created = Time.at(node_obj.created)
        node.creator = @users[node_obj.uid]
        node.tags = []
        node_obj.term_node.each do |tn|
            if @tags[tn.tid]
                node.tags << @tags[tn.tid]
            end
        end

        node.content = get_node_content(node_obj)
        node.is_published = (node_obj.status == 1 ? true : false)
        node.is_page = (node_obj.type == 'page' ? true : false)
        node.is_blog = (node_obj.type == 'blog' ? true : false)

        node.root_comments = get_node_comments(node_obj, node.relative_url)

        node.attachments = get_node_attachments(node_obj)
                     
        node
    end

    ### Given a URL (relative or absolute) tests if it is a link to
    ### a something on the Drupal site.  Doesn't actually verify the link points to a valid node
    ### (that's what does_node_url_exist does); just verifies that
    ### a something SHOULD exist at that URL
    def is_internal_url(parent_url, url)
        # If the path from the base url to this URL is relative, this is a link
        # to something on the site.
        route = get_url_relative_to_base(parent_url, url)
        @logger.log_trace "Route to '#{url}' from '#{@baseurl}' is '#{route}'"
        if route.relative?
            @logger.log_trace "'#{url}' is relative to base URL"
            true
        else
            @logger.log_trace "'#{url}' is not relative to base URL"
            false
        end
    end


    ### Given a URL that points to somewhere on the Drupal site (according to
    ### is_internal_url), looks for a node or file attachment at that URL
    ### If nothing is found, returns false, else returns true
    def does_internal_url_exist(parent_url, url)
        get_internal_object_from_url(parent_url, url) != nil
    end

    ### Given a URL that points to somewhere on the Drupal site (according to
    ### is_internal_url), looks for a node or file attachment at that URL
    ### If nothing is found, returns nil, else returns the absolute URL of the object
    def get_internal_object_url_from_url(parent_url, url)
        # Compute the URL of this content relative to the base URL of the site
        relative_url = get_url_relative_to_base(parent_url, url)
        @logger.log_trace "Route to '#{url}' from '#{@baseurl}' is '#{relative_url}'"

        if !relative_url.relative?
            @logger.log_trace("URL #{url} is not relative to #{@baseurl} so returning nil for internal object URL")
            return nil
        end

        # If this is a node/<nodeid> URL, look for a node with that ID
        if relative_url.path =~ /node\/(\d+)/
            node_id = $1.to_i()

            node = DrupalModel::Node.find(:first, :conditions => {:nid => node_id})
            if node != nil
                @logger.log_trace "Url '#{url}' points to node ID #{node_id}"
                #If there's a URL alias for this node, use that, else just use the raw node URL
                if @url_aliases.has_key?(relative_url.path)
                    @logger.log_trace("URL '#{url}' node ID #{node_id} has URL alias '#{@url_aliases[relative_url.path]}'; using alias for node URL")
                    @baseurl.merge(@url_aliases[relative_url.path])
                else
                    @logger.log_trace("URL '#{url}' node ID #{node_id} does not have a URL alias; using raw node URL")
                    @baseurl.merge(relative_url.path)
                end
            else
                @logger.log_trace "Url '#{url}' points to non-existent node ID #{node_id}"
                nil
            end
        else
            #Doesn't look like a node URL.  Look for a URL alias
            if @url_alias_sources.has_key?(relative_url.path)
                @logger.log_trace "URL '#{relative_url.path}' corresponds to a URL alias"
                @baseurl.merge(relative_url.path)
            elsif @files.has_key?(CGI.unescape(relative_url.path))
                #Only other thing it could be is a file attachment. 
                @logger.log_trace "URL '#{relative_url}' corresponds to a file attachment"
                @baseurl.merge(relative_url.path)
            elsif relative_url.to_s.length == 0
                #This is a link back to the main site
                @baseurl
            else
                @logger.log_trace "URL '#{relative_url}' doesn't correspond to any Drupal content"
                nil
            end
        end
    end

    # Given a URL relative to the base URL of the Drupal site, determines if the given URL
    # corresponds to a Drupal file attachment
    def is_internal_url_file_attachment(relative_url)
        #The URL may or may not have things like spaces and such escaped out, but in the Drupal
        #database such things are never escaped
        relative_url = CGI.unescape(relative_url)

        return @files.has_key?(relative_url)
    end

    ### Given a URL encountered within a page with URL parent_url, returns
    ### a URL relative to @baseurl.  If url is an asbolute URL just returns that
    def get_url_relative_to_base(parent_url, url)
        # Parse url by itself; if it is a relative URL, parse it relative
        # to parent_url
        canonicalized_url = URI.parse(url).normalize()
        if canonicalized_url.relative?
            canonicalized_url = URI.parse(parent_url).merge(url).normalize()
        end

        #If the scheme, userinfo, host, port, and registry match between this URL
        #and the base URL, then convert to a URL relative to the base
        #otherwise just return the absolute URL
        if canonicalized_url.scheme == @baseurl.scheme &&
            canonicalized_url.userinfo == @baseurl.userinfo &&
            canonicalized_url.host == @baseurl.host &&
            canonicalized_url.port == @baseurl.port &&
            canonicalized_url.registry == @baseurl.registry &&
            canonicalized_url.path.index(@baseurl.path) == 0
            @logger.log_trace "Canonicalized URL '#{canonicalized_url}' is a child of base URL '#{@baseurl}'"
            @baseurl.route_to(canonicalized_url)
        else
            @logger.log_trace "Canonicalized URL '#{canonicalized_url}' is not a child of the base URL"
            canonicalized_url
        end
    end

    def title
        site_name = DrupalModel::Variable.get_variable("site_name")
        slogan = DrupalModel::Variable.get_variable("site_slogan")

        if slogan
            site_name + " - " + slogan
        else
            site_name
        end
    end

    def description
        DrupalModel::Variable.get_variable("site_mission")
    end

    def pub_date
        Time.at(DrupalModel::Node.maximum(:created))
    end

    def default_locale
        defloc = DrupalModel::LocalesMeta.find(:first, :conditions => {:isdefault => 1})
        if defloc
            defloc.locale
        else
            # Default to en
            "en"
        end
    end

    def num_nodes
        @num_nodes
    end

    def each_tag(&block)
        @tags.each do |key,value|
            block.call(value)
        end
    end

    def each_category(&block)
        # TODO: Implement this.  Should enumerate all vocabulary rows with module = 'taxonomy' and tag = 0
        # and surface them as categories.  I don't use that feature so I've not implemented it
    end

    # Computes the canonical node/id URL that all nodes have
    def compute_canonical_node_url(node)
        "node/#{node.nid}"
    end

    # Checks to see if a URL alias is registered for the given canonical node URL, returning
    # the alias if found or the canonical URL if not
    def compute_alias_url(canonical_url)
        @url_aliases[canonical_url] || canonical_url
    end

    def find_all_tags
        # Find the "Tags" vocabulary
        DrupalModel::Vocabulary.find(:first, :conditions => {:module => 'taxonomy', :tags => 1})
    end

    def get_node_content(node)
        rev = get_latest_node_revision(node)
        if rev
            #Strip the break marker <!--break--> .  I can't figure out where in the WXR the excerpt goes so there's no way to preserve this
            #in the wordpress export, and if we don't strip it it might get interpreted as markdown 
            rev.body.sub!('<!--break-->', '')
            decode_content_format(rev.format, rev.body)
        else
            nil
        end
    end

    def get_latest_node_revision(node)
        if node.node_revisions.length > 0
            #Find the highest revision
            node.node_revisions[node.node_revisions.length - 1]
        else
            nil
        end
    end

    def get_node_comments(node, relative_url)
        # Comments are hierarchical, but for performance reasons retrieve all comments for a node and process them recursively
        comments = node.comments

        # The root comment list will contain comments with no parent (pid = 0)
        # Each of those comments may contain replies, and so on
        comments = get_comments_for_parent(comments, 0)

        # If the user has specified a disqus comments XML file, pull those in as well
        disqus_comments = get_disqus_comments_for_node(node, relative_url)

        comments = comments.concat(disqus_comments) unless disqus_comments == nil

        comments
    end

    def get_comments_for_parent(comment_objects, pid)
        comments = []

        comment_objects.each do |comment_object|
            if comment_object.pid == pid
                comment = OpenStruct.new

                comment.comment_id = comment_object.cid
                comment.title = comment_object.subject

                begin
                    comment.content = decode_content_format(comment_object.format, comment_object.comment) 
                rescue
                    @logger.log_exception $!, "Unable to decode content for comment ID #{comment_object.cid}.  Undecoded content will be migrated instead"
                    comment.content = comment_object.comment
                end

                #If the user didn't type a title, Drupal uses the first few words from the body, stripped of any markup.  
                #In that case, there is no title
                if comment.content != nil &&
                    comment.content.length >= comment.title.length &&
                    comment.title == comment.content.gsub(/<\/?[^>]*>/, "")[0..comment.title.length-1]
                    comment.title = nil
                end

                comment.hostname = comment_object.hostname
                comment.timestamp = Time.at(comment_object.timestamp)
                comment.is_published = comment_object.status == 0 ? true : false
                comment.poster_name = comment_object.name
                comment.poster_email = comment_object.mail
                comment.poster_url = comment_object.homepage

                comment.replies = get_comments_for_parent(comment_objects, comment_object.cid)

                comments << comment
            end
        end

        comments
    end

    def get_disqus_comments_for_node(node, relative_url)
        return unless @disqus_comments != nil

        #Disqus comments are grouped by articles, with each article identified by the fully-qualified URL
        #of the page where the article appears.
        @logger.log_trace "Getting disqus comments for article with base URL [#{@baseurl}], relative URL [#{relative_url}]"
        article_url = URI.join(@baseurl.to_s(), relative_url)

        @disqus_comments[article_url.to_s()]
    end

    def get_node_attachments(node_obj)
        attachments = []

        rev = get_latest_node_revision(node_obj)
        rev.upload.each do |upload|
            file = upload.file

            attachment = OpenStruct.new

            attachment.is_visible = upload.list == 1 ? true : false
            attachment.description = upload.description
            attachment.attachment_id = upload.fid
            attachment.filename = file.filename
            attachment.filepath = file.filepath
            attachment.mime_type = file.filemime
            attachment.size = file.filesize

            attachments << attachment
        end

        attachments
    end

    def decode_disqus_comment(comment_in)
        # Replace double newlines with <p> marks, and unescape HTML
        comment_out = "<p>" + CGI.unescapeHTML(comment_in) + "</p>"
        comment_out.gsub!("\n\n", "</p>\n\n<p>")
    end

    def decode_content_format(format, content)
        #Translate this if it's textile or markdown 
        if @textile_formats.include?(format)
            textile_to_xhtml(content)
        elsif @markdown_formats.include?(format)
            markdown_to_xhtml(content)
        else
            #Just return the body verbatim
            content
        end
    end

    def textile_to_xhtml(textile)
        RedCloth.new(textile).to_html
    end

    def markdown_to_xhtml(markdown)
        # The marksmarty module in drupal combines the SmartyPants intelligent quoting library
        # with markdown text-to-HTML conversion
        #BlueCloth.new(RubyPants.new(markdown).to_html).to_html
        BlueCloth.new(markdown).to_html
    end

    def load_disqus_comments(file)
        # Extracts the disqus comments from an XML file and stores them keyed by the absolute URL of the post
        # they correspond to
        disqus_comments = {}

        doc = REXML::Document.new(file)

        REXML::XPath.each(doc, "//article") do |article|
            article_url = article.elements['url'].text

            comments = []
            article.elements.each('comments/comment') do |comment_element|
                comment = OpenStruct.new

                comment.comment_id = DISQUS_COMMENT_ID
                comment.title = DISQUS_COMMENT_SUBJECT

                # Disqus comments seem to be quasi-textual, but HTML is allowed too.
                # HTML is escaped with &gt; and such, and mal-formed HTML isn't corrected
                comment.content = decode_disqus_comment(comment_element.elements["message"].text)
                comment.hostname = comment_element.elements["ip_address"].text
                comment.timestamp = Time.parse(comment_element.elements["date"].text)
                comment.is_published = true
                comment.poster_name = comment_element.elements["name"].text
                comment.poster_email = comment_element.elements["email"].text
                comment.poster_url = comment_element.elements["url"].text

                # Disqus supports threaded dicussions, but doesn't reflect the threaded structure in XML
                # exports, sadly
                comment.replies = []

                @logger.log_trace "Loaded comment for article [#{article_url}]: #{comment.content}"
                comments << comment
            end

            disqus_comments[article_url] = comments
        end

        disqus_comments
    end
end

