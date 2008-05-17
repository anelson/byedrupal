
module DrupalModel
    class TermNode < Base    
        self.table_name = 'term_node'
        self.primary_key = 'tid,nid'
    end                                                                          
end
