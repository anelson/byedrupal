# ActiveRecord model object representing a drupal Node object

module DrupalModel
    class Node < Base
        belongs_to :user, :class_name => "DrupalModel::User", :foreign_key => "uid"
        has_many :term_node, :class_name => "DrupalModel::TermNode", :foreign_key => "nid"
        has_many :node_revisions, :class_name => "DrupalModel::NodeRevision", :foreign_key => "nid"
        has_many :comments, :class_name => "DrupalModel::Comment", :foreign_key => "nid"

        self.table_name = 'node'
        self.primary_key = 'nid'
    
        # The node table has a 'type' column which has special significance in Ruby
        # per http://www.benlog.org/2007/1/16/legacy-rails-beware-of-type-columns work
        # around that by disabling single table inheritance and exposting the type property
        # as a different name
        def self.inheritance_column
            nil
        end
        def node_type
            attr_reader :type
        end
        def node_type=(type)
            attr_writer :type, type
        end
    end          
end                                                                
