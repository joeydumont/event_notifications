module EventNotification
  module Patches
    module DocumentPatch

      def self.included(base) # :nodoc:
        #base.send(:include, InstanceMethods)
        base.extends(InstanceMethods)
        #base.class_eval do
        #  unloadable
        #  alias_method_chain :notified_users, :events
        #end
      end

      module InstanceMethods
  	    def notified_users
          return [] if User.current.ghost? || User.current.admin_ghost? || User.get_notification == false
          if Setting.plugin_event_notifications["enable_event_notifications"] == "on"
    	      notified =  project.notified_users(self)
    	      notified.reject! {|user| !visible?(user)} unless project.notify_non_member
    	      notified
          else
            super
          end
  	    end
      end
    end
  end
end

unless Document.included_modules.include? EventNotification::Patches::DocumentPatch
  Document.send(:include, EventNotification::Patches::DocumentPatch)
end
