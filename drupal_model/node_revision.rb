module DrupalModel
    class NodeRevision < Base
        belongs_to :node, :class_name => "DrupalModel::Node", :foreign_key => "nid"
        has_many :upload, :class_name => "DrupalModel::Upload", :foreign_key => "vid"

        self.table_name = 'node_revisions'
        self.primary_key = 'vid'
    end          
end                                                                
