# Config class to setup connection to Drupal database
require 'active_record'

module DrupalModel
    class Config
        def self.setup(args)
            ActiveRecord::Base.establish_connection(
                args
            )
    
            ActiveRecord::Base.logger = Logger.new("activerecord.log")

            # Make sure MySQL adapter uses UTF-8
            # per http://ruphus.com/blog/2005/06/23/getting-unicode-mysql-and-rails-to-cooperate/
            ActiveRecord::Base.connection.execute 'SET NAMES UTF8'
        end
    end
end


