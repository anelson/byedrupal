module DrupalModel
    class Upload < Base
        self.table_name = 'upload'
        self.primary_key = 'fid'

        has_one :file, :class_name => "DrupalModel::File", :foreign_key => "fid"
    end          
end                                                                

