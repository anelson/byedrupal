require File.dirname(__FILE__) + '/../php_serialize'

module DrupalModel
    class Variable < Base
        self.table_name = 'variable'
        self.primary_key = 'name'
    
        def deserialized_value
            PHP.unserialize(value)
        end
    
        def self.get_variable(name)
            var = self.find(:first, :conditions => {:name => name})
            if var
                var.deserialized_value
            else
                nil
            end
        end
    end                                                                          

end
