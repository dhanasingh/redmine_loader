module Concerns::Importxml
  extend ActiveSupport::Concern

  def build_tasks_to_import(raw_tasks)
    tasks_to_import = []
    raw_tasks.each do |index, task|
      struct = ImportTask.new
      fields = %w(tid subject status_id level outlinenumber code estimated_hours start_date due_date priority done_ratio predecessors delays assigned_to parent_id description milestone tracker_id is_private uid spent_hours cf_text1 cf_text2 cf_text3 cf_text4 cf_number1 cf_number2 cf_number3 cf_date1 cf_date2 cf_date3)

      (fields - @ignore_fields['import']).each do |field|
        eval("struct.#{field} = task[:#{field}]#{".try(:split, ', ')" if field.in?(%w(predecessors delays))}")
      end
      struct.status_id ||= IssueStatus.default
      struct.done_ratio ||= 0
      tasks_to_import[index.to_i] = struct
    end
    return tasks_to_import.compact.uniq
  end

  def get_tasks_from_xml(doc)

    # Extract details of every task into a flat array

    tasks = []
    @unprocessed_task_ids = []

    logger.debug "DEBUG: BEGIN get_tasks_from_xml"

    tracker_field = doc.xpath("Project/ExtendedAttributes/ExtendedAttribute[FieldName='Text16']/FieldID").try(:text).try(:to_i)
    issue_rid = doc.xpath("Project/ExtendedAttributes/ExtendedAttribute[FieldName='Text15']/FieldID").try(:text).try(:to_i)
    redmine_task_status = doc.xpath("Project/ExtendedAttributes/ExtendedAttribute[FieldName='Text14']/FieldID").try(:text).try(:to_i)
	clientEstimateField = doc.xpath("Project/ExtendedAttributes/ExtendedAttribute[FieldName='Text17']/FieldID").try(:text).try(:to_i)
	completionDateField = doc.xpath("Project/ExtendedAttributes/ExtendedAttribute[FieldName='Date5']/FieldID").try(:text).try(:to_i)
	
	settings ||= Setting.plugin_redmine_loader
	
	eaCfHash = getMappedCfAttribures(doc, settings)
	
    default_issue_status_id = IssueStatus.first.id

    doc.xpath('Project/Tasks/Task').each do |task|
      begin
        logger.debug "Project/Tasks/Task found"
        struct = ImportTask.new
        struct.uid = task.value_at('UID', :to_i)
        next if struct.uid == 0
        struct.milestone = task.value_at('Milestone', :to_i)
        #next unless struct.milestone.try(:zero?)
        status_name = task.xpath("ExtendedAttribute[FieldID='#{redmine_task_status}']/Value").try(:text)
        struct.status_id = status_name.present? ? IssueStatus.find_by_name(status_name).id : default_issue_status_id
        struct.level = task.value_at('OutlineLevel', :to_i)
        struct.outlinenumber = task.value_at('OutlineNumber', :strip)
        struct.subject = task.at('Name').text.strip
        struct.start_date = task.value_at('Start', :split, "T").try(:fetch, 0)
        struct.due_date = task.value_at('Finish', :split, "T").try(:fetch, 0)
        struct.spent_hours = task.at('ActualWork').try{ |e| e.text.delete("PT").split(/H|M|S/)[0...-1].join(':') }
        struct.priority = task.at('Priority').try(:text)
        struct.tracker_name = task.xpath("ExtendedAttribute[FieldID='#{tracker_field}']/Value").try(:text)
        struct.tid = task.xpath("ExtendedAttribute[FieldID='#{issue_rid}']/Value").try(:text).try(:to_i)
        struct.estimated_hours = task.at('Duration').try{ |e| e.text.delete("PT").split(/H|M|S/)[0...-1].join(':') } #if struct.milestone.try(:zero?)
        struct.done_ratio = get_percent_complete(task).round(-1)
        struct.description = task.value_at('Notes', :strip)
        struct.predecessors = task.xpath('PredecessorLink').map { |predecessor| predecessor.value_at('PredecessorUID', :to_i) }
        struct.delays = task.xpath('PredecessorLink').map { |predecessor| predecessor.value_at('LinkLag', :to_i) }
		eaCfHash.each do|attr, fieldId|
			struct[attr] = task.xpath("ExtendedAttribute[FieldID='#{fieldId}']/Value").try(:text)
			unless task.xpath("ExtendedAttribute[FieldID='#{fieldId}']/Value").try(:text).blank?
				struct[attr] = task.xpath("ExtendedAttribute[FieldID='#{fieldId}']/Value").try(:text).try(:split, "T").try(:fetch, 0) if attr.include? "date"
			end
		end
        tasks.push(struct)

      rescue => error
        logger.debug "DEBUG: Unrecovered error getting tasks: #{error}"
        @unprocessed_task_ids.push task.value_at('ID', :to_i)
      end
    end

    tasks = tasks.compact.uniq.sort_by(&:uid)

    set_assignment_to_task(doc, tasks)
    logger.debug "DEBUG: Tasks: #{tasks.inspect}"
    logger.debug "DEBUG: END get_tasks_from_xml"
    return tasks
  end


  def set_assignment_to_task(doc, tasks)
    resource_by_user = get_bind_resource_users(doc)
    doc.xpath('Project/Assignments/Assignment').each do |as|
      resource_id = as.at('ResourceUID').text.to_i
      next if resource_id == Importxml::NOT_USER_ASSIGNED
      task_uid = as.at('TaskUID').text.to_i
      assigned_task = tasks.detect { |task| task.uid == task_uid }
      next unless assigned_task
      assigned_task.assigned_to = resource_by_user[resource_id]
	  if assigned_task.work.blank?
		 assigned_task.work = as.at('Work').try{ |e| e.text.delete("PT").split(/H|M|S/)[0...-1].join(':') }
	  else	
		work = as.at('Work').try{ |e| e.text.delete("PT").split(/H|M|S/)[0...-1].join(':') } 
		assigned_task.work = get_scorm_time((assigned_task.work.try(:to_hours)).to_f + (work.try(:to_hours)).to_f)
	  end
    end
  end
  
  def get_scorm_time time
    return 'PT8H0M0S' if time.nil? || time.zero?
    time = time.to_s.split('.')
    hours = time.first.to_i
    minutes = time.last.to_i == 0 ? 0 : (60 * "0.#{time.last}".to_f).to_i
    return "PT#{hours}H#{minutes}M0S"
  end
  
  def get_percent_complete(task)  
	duration  = task.at('Duration').try{ |e| e.text.delete("PT").split(/H|M|S/)[0...-1].join(':') }
	remainingDuration = task.at('RemainingDuration').try{ |e| e.text.delete("PT").split(/H|M|S/)[0...-1].join(':') }
	percentComplete = (((duration.try(:to_hours).to_f - remainingDuration.try(:to_hours).to_f) / duration.try(:to_hours).to_f) * 100)
	percentComplete.to_i
  end

  def get_bind_resource_users(doc)
    resources = get_resources(doc)
    users_list = @project.assignable_users
    resource_by_user = {}
    resources.each do |uid, name|
      user_found = users_list.detect { |user| (user.login || user.lastname) == name }
      next unless user_found
      resource_by_user[uid] = user_found.id
    end
    return resource_by_user
  end

  def get_resources(doc)
    resources = {}
    doc.xpath('Project/Resources/Resource').each do |resource|
      resource_uid = resource.value_at('UID', :to_i)
      resource_name_element = resource.value_at('Name', :strip)
      next unless resource_name_element
      resources[resource_uid] = resource_name_element
    end
    return resources
  end
  
  def getMappedCfAttribures(doc, settings)
	eaCfHash = Hash.new
	['text', 'number', 'date'].each do |eaType|
		exAttrCount = eaType == 'text' ? 4 : 3
		for i in 1..exAttrCount
			attrName = eaType + i.to_s
			exAttrName = settings['loader_extended_' + attrName]
			cfId = settings['loader_cf_' + attrName]
			unless exAttrName.blank? || (cfId.blank? || cfId.to_i == 0 )
				eaCfHash['cf_' + attrName] = doc.xpath("Project/ExtendedAttributes/ExtendedAttribute[FieldName='#{exAttrName}']/FieldID").try(:text).try(:to_i)
			end
		end
	end
	eaCfHash
  end
end
