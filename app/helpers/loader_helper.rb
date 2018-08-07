module LoaderHelper
  include Redmine::Utils::DateCalculation
	
  def loader_user_select_tag(project, assigned_to, index)
    select_tag "import[tasks][#{index}][assigned_to]", options_from_collection_for_select(project.assignable_users, :id, :name, assigned_to ), { include_blank: true }
  end

  def loader_tracker_select_tag(project, tracker_name, index)
    tracker_id = if map_trackers.has_key?(tracker_name)
                   map_trackers[tracker_name]
                 else
                   @settings['import']['tracker_id']
                 end
    select_tag "import[tasks][#{index}][tracker_id]", options_from_collection_for_select(project.trackers, :id, :name, tracker_id)
  end

  def loader_percent_select_tag(task_percent, index)
    select_tag "import[tasks][#{index}][done_ratio]", options_for_select((0..10).to_a.map {|p| (p*10)}, task_percent)
  end

def loader_priority_select_tag(task_priority, index)
    # priority_name = case task_priority.to_i
               # when 0..200 then 'Minimal'
               # when 201..400 then 'Low'
               # when 401..600 then 'Normal'
               # when 601..800 then 'High'
               # when 801..1000 then 'Immediate'
               # end
	# priorityId = map_priority[priority_name]
    select_tag "import[tasks][#{index}][priority]", options_from_collection_for_select(IssuePriority.active, :id, :name, task_priority.to_i)
  end

  def ignore_field?(field, way)
    field.to_s.in?(@ignore_fields.send(:fetch, way))
  end

  def duplicate_index task_subject
    @duplicates.index(task_subject).next if task_subject.in?(@duplicates)
  end

  def map_trackers
    @map_trackers ||= Hash[@project.trackers.map { |tracker| [tracker.name, tracker.id] }]
  end
  
  def map_priority
	@map_priority ||= Hash[IssuePriority.active.map { |priority| [priority.id, priority.name] }]
  end
  
  def getCfListArr(customFields, cfType, needBlank)
	unless customFields.blank?
		cfs = customFields.select {|cf| cf.field_format.in? (cfType) }
		unless cfs.blank?
			cfArray = cfs.collect {|cf| [cf.name, cf.id] }
		else
			cfArray = Array.new
		end
	else
		cfArray = Array.new
	end
	cfArray.unshift(["",0]) if needBlank
	cfArray
  end
  
  def getExtentedAttr(attrType, ingnoreIds=nil, needBlank=true)
	extendAttrCount = getExtentedAttrCount(attrType)
	extendAttr = ('1'.. extendAttrCount).to_a.collect { |x| attrType + x }
	extendAttr.unshift('') if needBlank
	extendAttr
  end
  
  def getExtentedAttrFieldId(attrType=nil)
	extendAttrHash = Hash.new
	case attrType
	   when 'Text' then
			extendAttrHash = getTextAttributes
	   when 'Date' then
			extendAttrHash = getDateAttributes
	   when 'Number' then
			extendAttrHash = getNumberAttributes
		else
			extendAttrHash = getNumberAttributes.merge(getTextAttributes.merge(getDateAttributes))
	   end
	extendAttrHash
  end
  
  def getTextAttributes
	textFieldHash =  Hash.new
	incrementBy = 3
	initFieldId = 188743731
	# For the first 6 text fieldIds are increment by 3 after that it increment by 1 in project libre
	# After 188743750 next field id is 188743997 so we have add the 246
	for i in 1..30
		textFieldHash['Text' + i.to_s] = initFieldId
		incrementBy = 1  if initFieldId == 188743746
		initFieldId = initFieldId + 246 if initFieldId == 188743750
		initFieldId = initFieldId + incrementBy
	end
	textFieldHash
  end
  
  def getDateAttributes
	dateAttrHash = Hash.new
	for i in 1..10
		dateAttrHash['Date' + i.to_s] = 188743944 + i
	end
	dateAttrHash
  end
  
  def getNumberAttributes
	numAttrHash = Hash.new
	initFieldId = 188743766	
	for i in 1..20
		numAttrHash['Number' + i.to_s] = initFieldId + i
		# Number fieldIds are not sequential there is jump after 188743771 Number5 so we add that here 
		initFieldId = initFieldId + 210 if initFieldId + i == 188743771
	end
	numAttrHash
  end
  
  def getExtentedAttrCount(attrType)
	extendAttrCount = case attrType
               when 'Text' then '30'
               when 'Date' then '10'
               when 'Number' then '20'
               end
	extendAttrCount
  end
  
	def getMappedAttrCF
		attrCfHash = Hash.new
		['text', 'number', 'date'].each do |eaType|
			exAttrCount = eaType == 'text' ? 4 : 3
			for i in 1..exAttrCount
				attrName = eaType + i.to_s
				exAttrName = @settings['loader_extended_' + attrName]
				cfId = @settings['loader_cf_' + attrName]
				unless exAttrName.blank? || (cfId.blank? || cfId.to_i == 0 )
					attrCfHash[exAttrName] = cfId.to_i
				end
			end
		end
		attrCfHash
	end
end
