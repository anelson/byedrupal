# Stuplid class to do XML/HTML escaping
module XmlEscape
    def XmlEscape.escape(str)
        result = str
        if str.kind_of?(String)
            result = result.gsub("&", "&amp;")
            result.gsub!("<", "&lt;")
            result.gsub!(">", "&gt;")
            result.gsub!("'", "&apos;")
            result.gsub!("\"", "&quot;")
        end

        result
    end
end
