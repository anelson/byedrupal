# Logs events during conversion, which are written to a collection of XHTML files
# for easy consumption
require 'time'

require File.dirname(__FILE__) + '/xml_escape'
include XmlEscape

class ConversionLogger
    LOG_LEVEL_ERROR = 0
    LOG_LEVEL_WARNING = 1
    LOG_LEVEL_INFO = 2
    LOG_LEVEL_DEBUG = 3
    LOG_LEVEL_TRACE = 4

    # Static method which creates a new logger object and passes it to 
    # &block.  When block returns, the log is flushed
    def self.do_conversion(opts, &block)
        instance = ConversionLogger.new(opts)

        begin
            block.call(instance)
        rescue NoMethodError,NameError,TypeError
            # These are usually due to compiler errors and shouldn't be hidden
            instance.close
            raise
        rescue
            instance.log_exception $!
            instance.log_error "Converstion aborted due to unhandled exception"

            # Also write to stdout so it's obvious something is wrong
            puts "Conversion aborted to unhandled exception.  See log file for more details.  Exception: #{$!}"
        end

        instance.close
    end

    # Starts a new log file for the conversion of a specific node, yields
    # to &block, and closes the log file when &block returns.  If &block
    # throws, the exception details are logged in the node log file
    def do_node_conversion(node_id, node_title, node_record, &block)
        start_node_log node_id, node_title, node_record
        begin
            block.call(self)
        rescue NoMethodError,NameError,TypeError
            # These are usually due to compiler errors and shouldn't be hidden
            end_node_log
            raise
        rescue
            log_exception $!
            log_error "Converstion of node aborted due to unhandled exception"
        end
        end_node_log
    end

    def message_count(log_level)
        @node_message_counts[log_level]
    end

    def index_filename
        @index_filename
    end

    def log_error(msg)
        log LOG_LEVEL_ERROR, msg
    end

    def log_error_html(msg)
        log_html LOG_LEVEL_ERROR, msg
    end

    def log_warning(msg)
        log LOG_LEVEL_WARNING, msg
    end

    def log_warning_html(msg)
        log_html LOG_LEVEL_WARNING, msg
    end

    def log_info(msg)
        log LOG_LEVEL_INFO, msg
    end

    def log_info_html(msg)
        log_html LOG_LEVEL_INFO, msg
    end

    def log_debug(msg)
        log LOG_LEVEL_DEBUG, msg
    end

    def log_debug_html(msg)
        log_html LOG_LEVEL_DEBUG, msg
    end

    def log_trace(msg)
        log LOG_LEVEL_TRACE, msg
    end

    def log_trace_html(msg)
        log_html LOG_LEVEL_TRACE, msg
    end

    def log_exception(exception, context = nil)
        msg = String.new
        if context
            msg << context << " - Exception details: "
        else
            msg << "Unhandled exception "
        end
        msg << "<span class='code exceptionClass'>#{exception.class}</span>:"
        msg << "<span class='exceptionMessage'>#{exception.message}</span>"
        msg << "<div class='exceptionStackTrace'>Stack trace: "
        exception.backtrace.each do |stack_frame|
            msg << "<div class='code stackFrame'>#{stack_frame}</div>"
        end
        msg << "</div>"

        log_error_html(msg)
    end

    def log(log_level, msg)
        log_html(log_level, XmlEscape::escape(msg))
    end

    # Like log(), but does not escape HTML reserved characters like '<' and '>'
    def log_html(log_level, msg)
        if @log_to_stdout
            log_to_text_file STDOUT, log_level, msg
        end

        if @node_file
            log_to_html_file @node_file, log_level, msg
        else
            log_to_html_file @index_file, log_level, msg
        end
    end

    def close
        end_log_file @index_file

        @index_file.close
        @index_file = nil
    end

    private 

    def initialize(opts)
        @logdir = opts[:logdir] || (raise ArgumentError, "Missing logdir")

        if !File.exists?(@logdir)
            Dir.mkdir(@logdir)
        end
        
        @index_filename = File.join(@logdir, 'index.html')
        @index_file = File.new(@index_filename, 'w')
        
        @log_level = opts[:log_level] || LOG_LEVEL_INFO

        @debug = @log_level >= LOG_LEVEL_DEBUG
        @trace = @log_level >= LOG_LEVEL_TRACE
        @log_to_stdout = opts[:log_to_stdout]

        start_log_file @index_file, "Drupal to Wordpress Conversion Initiated #{Time.new}"
    end

    # Writes the XHTML preamble and head for a log file
    def start_log_file(file, title)
        file << 
<<EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
<title>
EOS
        file << title
        file << 
<<EOS
</title>
<style type="text/css">
    body {font-family: Verdana,Arial,Sans Serif; padding: 0%; margin: 0% }
    
    tr.logEntry { vertical-align: top; }
    tr.logEntry.info  { background-color: #00ff80; }
    tr.logEntry.warning  { background-color: yellow; }
    tr.logEntry.error  { background-color: red; }
    tr.logEntry.debug { background-color: ltgray; }
    tr.logEntry.trace { background-color: none; }
    
    td.dtStampCell { white-space: nowrap; }
    
    span.nodeEventSummary { font-style: italic; white-space: nowrap; display: block;}
    span.nodeId { font-style: italic; font-weight: bold } 
    span.nodeTitle { font-style: italic; }
    
    span.exceptionClass, span.exceptionMessage, div.stackFrame {font-family: Courier New,Courier; background-color: gray; }
</style>

</head>

<body>
<table class='logEvents'>
<tr>
<th id='dtStampHeader'>Date/Time Stamp</th>
<th id='msgHeader'>Message</th>
</tr>
EOS

    end

    def end_log_file(file)
        file << 
<<EOS
</table>
</body>
</html>
EOS

    end

    # Creates a new log file for the node
    def start_node_log(node_id, node_title, node_record)
        @node_filename = "node-#{node_id}.html"
        @node_file = File.new(File.join(@logdir, @node_filename), 'w')
        @node_id = node_id
        @node_title = node_title
        @node_record = node_record
        @node_message_counts = {}
        @node_message_counts.default = 0

        start_log_file @node_file, "Conversion of node ID #{node_id}: #{node_title}"
    end

    def end_node_log
        end_log_file @node_file
        @node_file.close
        @node_file = nil

        # Write a log entry to the index file summarizing the results of the conversion of this node
        msg = String.new
        msg << "Converted node ID <span class='nodeId'>#{@node_id}</span>, "
        msg << "<span class='nodeTitle'>#{@node_title}</span>"
        msg << "<span class='nodeEventSummary'>"
        msg << " ["
        msg << "<span class='nodeEventCount nodeErrorCount'>#{@node_message_counts[LOG_LEVEL_ERROR]} error(s)</span>, "
        msg << "<span class='nodeEventCount nodeWarningCount'>#{@node_message_counts[LOG_LEVEL_WARNING]} warning(s)</span> - "
        msg << "<a href='#{@node_filename}' class='nodeLogLink'>Details</a>"
        msg << "]"
        msg << "</span>"

        if @node_message_counts[LOG_LEVEL_ERROR] > 0
            level = LOG_LEVEL_ERROR
        elsif @node_message_counts[LOG_LEVEL_WARNING] > 0
            level = LOG_LEVEL_WARNING
        else
            level = LOG_LEVEL_INFO
        end

        @node_filename = nil
        @node_id = nil
        @node_title = nil
        @node_record = nil
        @node_message_counts = nil

        log_html level, msg
    end

    def log_to_html_file(file, level, msg)
        return unless @log_level >= level

        if @node_message_counts
            @node_message_counts[level] += 1
        end

        now = Time.new

        file << "<tr class='logEntry"
        if level == LOG_LEVEL_ERROR
            file << " error"
        elsif level == LOG_LEVEL_WARNING
            file << " warning"
        elsif level == LOG_LEVEL_INFO
            file << " info"
        elsif level == LOG_LEVEL_DEBUG
            file << " debug"
        elsif level == LOG_LEVEL_TRACE
            file << " trace"
        else
            raise ArgumentError, "Invalid log level"
        end

        file << "'>"
        file << "<td class='dtStampCell'>#{now}</td>"
        file << "<td class='msgCell'>"
        file << msg
        file << "</td>"
        file << "</tr>"
        file << "\n"
    end

    def log_to_text_file(file, level, msg)
        return unless @log_level >= level

        if @node_message_counts
            @node_message_counts[level] += 1
        end

        if level == LOG_LEVEL_ERROR
            file << "ERROR: "
        elsif level == LOG_LEVEL_WARNING
            file << "WARNING: "
        elsif level == LOG_LEVEL_INFO
            file << "INFO: "
        elsif level == LOG_LEVEL_DEBUG
            file << "DEBUG: "
        elsif level == LOG_LEVEL_TRACE
            file << "TRACE: "
        else
            raise ArgumentError, "Invalid log level"
        end

        file << msg
        file << "\n"
    end
end
