module TraversingPatch
	def self.included(base)
        base.class_eval do
			# Returns the level of this object in the tree
			# root level is 0
			def level
			  parent_id.nil? ? 0 : ancestors.count
			end
		end
	end
end
