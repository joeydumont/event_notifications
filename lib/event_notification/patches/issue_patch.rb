module EventNotification
  module Patches
    module IssuePatch

      def self.included(base) # :nodoc:
        base.send(:include, InstanceMethods)
        base.extend(InstanceMethods)

        base.class_eval do
          unloadable

          validate :journal_admin_ghost, :if => Proc.new { |issue| !ActiveRecord::Base.record_timestamps && issue.current_journal.present? && !User.current.admin_ghost? } 

          before_save :set_new_issue_record
          #alias_method_chain :notified_users, :events
          #alias_method_chain :create_journal, :ghost
          #alias_method_chain :force_updated_on_change, :admin_ghost
        end
      end

      module InstanceMethods
        def journal_admin_ghost
          errors.add :base, l(:error_admin_ghost_mode)
        end

        def force_updated_on_change
          return if User.current.admin_ghost?
          super
        end

        def create_journal
          return if User.current.admin_ghost?
          current_journal.notify= false if User.current.ghost? && current_journal
          super
        end

        def set_new_issue_record
          @set_issue_record = new_record? ? 1 : 0
        end

        def is_issue_new_record?
          @set_issue_record ||= 0
        end

        def collect_related_issues
          logger.debug("Event Notifications : related issues.")
          # collect father, child and brother issues
          rel_issues = []
          self.relations.each do |relation|
            other_issue = relation.other_issue(self)
            relation_type = relation.relation_type_for(self)
            rel_issues << other_issue if relation_type == Setting.plugin_event_notifications["issue_involved_in_related_notified"]
            if relation_type == IssueRelation::TYPES[Setting.plugin_event_notifications["issue_involved_in_related_notified"]][:sym]
              father_issue = other_issue
              father_issue.relations.each do |father_issue_relation|
                father_other_issue = father_issue_relation.other_issue(father_issue)
                father_relation_type = father_issue_relation.relation_type_for(father_issue)
                rel_issues << father_other_issue if father_relation_type == Setting.plugin_event_notifications["issue_involved_in_related_notified"]
              end
            end
          end
          # logger.debug("Event Notifications : related issues collected : #{rel_issues.map(&:id).join(", ")}.")
          rel_issues.uniq
        end

        def collect_involved_related_users
          notified = []
          if Setting.plugin_event_notifications["issue_involved_in_related_notified"].present?
            logger.debug("Event Notifications : Colelcting related issues involved users.")
            # Author and assignee are always notified unless they have been locked or have refused that
            custom_field_users = []

            involved_issues = collect_related_issues

            return notified unless involved_issues.any?

            involved_issues.each do |issue|
              next if issue == self

              if issue.author && issue.author.active? && %w( all selected ).include?( issue.author.mail_notification ) &&
                  issue.author.pref[:involved_in_related_notified] == '1'
                # logger.debug("Event Notifications : Other issue #{issue.id} Author involved : #{issue.author}.")
                notified << issue.author
              end

              if issue.assigned_to && !issue.assigned_to.is_a?(Group) && issue.assigned_to.active? && %w( all selected ).include?( issue.author.mail_notification ) &&
                  issue.assigned_to.pref[:involved_in_related_notified] == '1'
                # logger.debug("Event Notifications : Other issue #{issue.id} Assignee involved : #{issue.assigned_to}.")
                notified << issue.assigned_to
              end

              issue.custom_values.each do |cv|
                next if cv.custom_field.field_format != 'user'
                custom_field_users << cv.value.to_i unless cv.value.nil?
              end
            end
            notified += User.active.where(:id => custom_field_users).select { |u| u.pref[:involved_in_related_notified] == '1' } if custom_field_users.any?
          end
          notified.each { |u| u.default_notifier=(true) }
          notified
        end

        def notified_users
          return [] if User.current.ghost? || User.current.admin_ghost? || User.get_notification == false
          if Setting.plugin_event_notifications["enable_event_notifications"] == "on"
            notified = []
            # Author and assignee are always notified unless they have been
            # locked or don't want to be notified
            notified << author if author
            if assigned_to
              notified += (assigned_to.is_a?(Group) ? assigned_to.users : [assigned_to])
            end
            if assigned_to_was
              notified += (assigned_to_was.is_a?(Group) ? assigned_to_was.users : [assigned_to_was])
            end
            # Collect users of User custom fields
            notified += User.where( :id => available_custom_fields.select {|f| f.field_format == 'user'}.map { |cf| custom_field_value(cf) }.reject(&:blank?).flatten ).to_a.each { |u| u.default_notifier=(true) }

            notified += collect_involved_related_users
            # logger.debug("Event Notifications : Current users selected : #{ notified.map(&:name).join(", ") }")
            notified =   notified.uniq.select {|u| u.active? && u.notify_about?(self)}
            # logger.debug("Event Notifications : Current users after check : #{ notified.map(&:name).join(", ") }")
            notified += project.notified_users_with_events(self)

            notified += [User.current] unless User.current.pref.no_self_notified

            notified.uniq!
            # Remove users that can not view the issue
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

unless Issue.included_modules.include? EventNotification::Patches::IssuePatch
  Issue.send(:include, EventNotification::Patches::IssuePatch)
end
