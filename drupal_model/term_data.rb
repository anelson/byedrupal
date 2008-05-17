
module DrupalModel
    class TermData < Base
        belongs_to :vocabulary, :class_name => "DrupalModel::Vocabulary", :foreign_key => "vid"
    
        self.table_name = 'term_data'
        self.primary_key = 'tid'
    end                                                                          
end
