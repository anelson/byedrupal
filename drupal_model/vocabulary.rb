module DrupalModel
    class Vocabulary < Base
        has_many :term_data, :class_name => "DrupalModel::TermData", :foreign_key => "vid"
    
        self.table_name = 'vocabulary'
        self.primary_key = 'vid'
    end                                                                          
end

