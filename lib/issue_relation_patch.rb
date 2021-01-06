module IssueRelationPatch
  def self.included(base)
    base.send(:include, InstanceMethods)
	
    base.class_eval do
	  include Redmine::Utils::DateCalculation
      alias_method :successor_soonest_start_without_working_days, :successor_soonest_start
      alias_method :successor_soonest_start, :successor_soonest_start_with_working_days
    end
  end


  module InstanceMethods
    def successor_soonest_start_with_working_days
		if (IssueRelation::TYPE_PRECEDES == self.relation_type) && delay && issue_from &&
			   (issue_from.start_date || issue_from.due_date)
		  add_working_days((issue_from.due_date || issue_from.start_date), (1 + delay))
		end
	end
  end
end
