module DrupalModel
    class Comment < Base
        self.table_name = 'comments'
        self.primary_key = 'cid'

        has_many :comments, :class_name => "DrupalModel::Comment", :foreign_key => "pid"
    end                                                                          
end

