module DrupalModel
    class User < Base
        has_many :node, :class_name => "DrupalModel::Node", :foreign_key => "uid"
    
        self.table_name = 'users'
        self.primary_key = 'uid'
    end                                                                          
end

