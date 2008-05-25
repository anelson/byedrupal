require File.dirname(__FILE__) + '/xml_escape'

include XmlEscape

class WxrWriter
    def initialize(outfile)
        @out = outfile
        @indent = 0
    end

    def start_file
        @out << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @out << OUTPUT_HEAD

        @indent = 2
    end

    def end_file
        @out << OUTPUT_FOOT
        @indent = 0
    end

    def start_rss_element(name, attrs)
        start_element(nil, name, attrs)
    end

    def end_rss_element(name)
        end_element(nil, name)
    end

    def write_rss_element(name, attrs, value)
        write_element(nil, name, attrs, value)
    end

    def write_rss_cdata_element(name, attrs, value)
        write_cdata_element(nil, name, attrs, value)
    end

    def start_rss_content_element(name, attrs)
        start_element("content", name, attrs)
    end

    def end_rss_content_element(name)
        end_element("content", name)
    end

    def write_rss_content_element(name, attrs, value)
        write_element("content", name, attrs, value)
    end

    def write_rss_content_cdata_element(name, attrs, value)
        write_cdata_element("content", name, attrs, value)
    end

    def start_commentapi_element(name, attrs)
        start_element("wfw", name, attrs)
    end

    def end_commentapi_element(name)
        end_element("wfw", name)
    end

    def write_commentapi_element(name, attrs, value)
        write_element("wfw", name, attrs, value)
    end

    def start_dublincore_element(name, attrs)
        start_element("dc", name, attrs)
    end

    def end_dublincore_element(name)
        end_element("dc", name)
    end

    def write_dublincore_element(name, attrs, value)
        write_element("dc", name, attrs, value)
    end

    def start_wordpress_element(name, attrs)
        start_element("wp", name, attrs)
    end

    def start_wordpress_element_nonewline(name, attrs)
        start_element_nonewline("wp", name, attrs)
    end

    def end_wordpress_element(name)
        end_element("wp", name)
    end

    def end_wordpress_element_nonewline(name)
        end_element_nonewline("wp", name)
    end

    def write_wordpress_element(name, attrs, value)
        write_element("wp", name, attrs, value)
    end

    def write_wordpress_element_nonewline(name, attrs, value)
        write_element_nonewline("wp", name, attrs, value)
    end

    def write_wordpress_cdata_element(name, attrs, value)
        write_cdata_element("wp", name, attrs, value)
    end

    def write_wordpress_cdata_element_nonewline(name, attrs, value)
        write_cdata_element_nonewline("wp", name, attrs, value)
    end

    def write_drupal_element(name, attrs, value)
        write_element("drupal", name, attrs, value)
    end

    def write_element(ns, name, attrs, value) 
        indent_line

        write_element_nonewline(ns, name, attrs, value)

        @out << "\n"
    end

    def write_element_nonewline(ns, name, attrs, value) 
        @out << "<"
        if ns
            @out << ns << ":"
        end
        @out << name
        if attrs
            attrs.each do |attrname,attrvalue|
                @out << " " << attrname << "=\"" << xmlencode(attrvalue) << "\""
            end
        end
        @out << ">" << xmlencode(value)

        @out << "</"
        if ns
            @out << ns << ":"
        end
        @out << name << ">"
    end

    def write_cdata_element(ns, name, attrs, value) 
        # I know what you're thinking; why is there a dedicated writer for cdata elements.
        # The reason is the programming gods who brought you wordpress didn't feel the WXR import logic
        # needed a proper XML parser, so they wrote the import code to 'parse' the WXR by finding
        # occurrences of tags and sucking in all data between them.  Unfortunately, the function
        # assumes a CDATA marker will, if present, always start immediately after the start of the element
        # containing it, with no possibility of whitespace.  You could be forgiven for thinking an XML format
        # built atop RSS would use, you know, XML, but you would be wrong.
        indent_line

        write_cdata_element_nonewline(ns, name, attrs, value)

        @out << "\n"
    end

    def write_cdata_element_nonewline(ns, name, attrs, value) 
        # I know what you're thinking; why is there a dedicated writer for cdata elements.
        # The reason is the programming gods who brought you wordpress didn't feel the WXR import logic
        # needed a proper XML parser, so they wrote the import code to 'parse' the WXR by finding
        # occurrences of tags and sucking in all data between them.  Unfortunately, the function
        # assumes a CDATA marker will, if present, always start immediately after the start of the element
        # containing it, with no possibility of whitespace.  You could be forgiven for thinking an XML format
        # built atop RSS would use, you know, XML, but you would be wrong.
        @out << "<"
        if ns
            @out << ns << ":"
        end
        @out << name
        if attrs
            attrs.each do |attrname,attrvalue|
                @out << " " << attrname << "=\"" << xmlencode(attrvalue) << "\""
            end
        end

        @out << "><![CDATA[" << value << "]]>"

        @out << "</"
        if ns
            @out << ns << ":"
        end
        @out << name << ">"
    end

    def write_text_value(value)
        indent_line

        @out << xmlencode(value) << "\n"
    end

    def write_cdata_value(value)
        indent_line
        @out << "<![CDATA[" << value << "]]>" << "\n"
    end

    def write_xml_value(value)
        indent_line
        @out << value << "\n"
    end

    def start_element(ns, name, attrs)
        start_element_nonewline(ns, name, attrs)

        @out << "\n"

        @indent += 1
    end

    def start_element_nonewline(ns, name, attrs)
        indent_line

        @out << "<"
        if ns
            @out << ns << ":"
        end
        @out << name
        if attrs
            attrs.each do |attrname,attrvalue|
                @out << " " << attrname << "=\"" << xmlencode(attrvalue) << "\""
            end
        end
        @out << ">"
    end

    def end_element(ns, name)
        @indent -= 1

        indent_line

        end_element_nonewline(ns, name)
    end

    def end_element_nonewline(ns, name)
        @out << "</"
        if ns
            @out << ns << ":"
        end
        @out << name << ">"

        @out  << "\n"

    end

    def indent_line
        @indent.times do 
            @out << "    "
        end
    end

    def xmlencode(txt)
        XmlEscape::escape(txt)
    end

    OUTPUT_HEAD = <<END_OF_STRING
<!-- This is a WordPress eXtended RSS file generated by WordPress as an export of your blog. -->
<!-- It contains information about your blog's posts, comments, and categories. -->
<!-- You may use this file to transfer that content from one site to another. -->
<!-- This file is not intended to serve as a complete backup of your blog. -->

<!-- To import this information into a WordPress blog follow these steps. -->
<!-- 1. Log into that blog as an administrator. -->
<!-- 2. Go to Manage: Import in the blog's admin panels. -->
<!-- 3. Choose "WordPress" from the list. -->
<!-- 4. Upload this file using the form provided on that page. -->
<!-- 5. You will first be asked to map the authors in this export file to users -->
<!--    on the blog.  For each author, you may choose to map to an -->
<!--    existing user on the blog or to create a new user -->
<!-- 6. WordPress will then import each of the posts, comments, and categories -->
<!--    contained in this file into your blog -->

<!-- generator="wordpress/2.3.3" created="2008-03-16 14:19"-->
<rss version="2.0"
    xmlns:content="http://purl.org/rss/1.0/modules/content/"
    xmlns:wfw="http://wellformedweb.org/CommentAPI/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:wp="http://wordpress.org/export/1.0/"
    xmlns:drupal="http://apocryph.org/drupal"
>

    <channel>
END_OF_STRING

    OUTPUT_FOOT = <<END_OF_STRING

    </channel>
</rss>
END_OF_STRING
end
