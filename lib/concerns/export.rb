module Concerns::Export
  extend ActiveSupport::Concern
  include LoaderHelper

  def generate_xml
    @uid = 1
    request_from = Rails.application.routes.recognize_path(request.referrer)
    get_sorted_query unless request_from[:controller] =~ /loader/
    @resource_id_to_uid = {}
    @task_id_to_uid = {}
    @version_id_to_uid = {}
    @calendar_id_to_uid = {}
	
	exAttrCfHash = getExtentedAttrFieldId
    export = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      resources = @project.assignable_users
      xml.Project('xmlns' => 'http://schemas.microsoft.com/project') {
        xml.Title @project.name + addRevision
		xml.Name @project.name + addRevision
		xml.ScheduleFromStart 1
        xml.ExtendedAttributes {
          xml.ExtendedAttribute {
            xml.FieldID 188744000
            xml.FieldName 'Text14'
            #xml.Alias @settings['redmine_status_alias']
          }
          xml.ExtendedAttribute {
            xml.FieldID 188744001
            xml.FieldName 'Text15'
            #xml.Alias @settings['redmine_id_alias']
          }
          xml.ExtendedAttribute {
            xml.FieldID 188744002
            xml.FieldName 'Text16'
            #xml.Alias @settings['tracker_alias']
          }
		  unless @settings['loader_percent_complete_attr'].blank?
			xml.ExtendedAttribute {
				xml.FieldID exAttrCfHash[@settings['loader_percent_complete_attr']]
				xml.FieldName @settings['loader_percent_complete_attr']
			}
		  end
		  getMappedAttrCF.each do |attr, cfId|
				xml.ExtendedAttribute {
				xml.FieldID exAttrCfHash[attr]
				xml.FieldName attr
			  }
		  end
        }
        xml.Calendars {
          xml.Calendar {
            xml.UID @uid
            xml.Name 'Standard'
            xml.IsBaseCalendar 1
            xml.IsBaselineCalendar 0
            xml.BaseCalendarUID 0
            xml.Weekdays {
              (1..7).each do |day|
                xml.Weekday {
                  xml.DayType day
                  if day.in?([1, 7])
                    xml.DayWorking 0
                  else
                    xml.DayWorking 1
                    xml.WorkingTimes {
                      xml.WorkingTime {
                        xml.FromTime '09:00:00'
                        xml.ToTime '13:00:00'
                      }
                      xml.WorkingTime {
                        xml.FromTime '14:00:00'
                        xml.ToTime '18:00:00'
                      }
                    }
                  end
                }
              end
            }
          }
          resources.each do |resource|
            @uid += 1
            @calendar_id_to_uid[resource.id] = @uid
            xml.Calendar {
              xml.UID @uid
              xml.Name resource.login
              xml.IsBaseCalendar 0
              xml.IsBaselineCalendar 0
              xml.BaseCalendarUID 1
            }
          end
        }
        xml.Tasks {
          xml.Task {
            xml.UID 0
            xml.ID 0
            xml.ConstraintType 0
            xml.OutlineNumber 0
            xml.OutlineLevel 0
            xml.Name @project.name
            xml.Type 1
            xml.CreateDate @project.created_on.to_s(:ms_xml)
          }

          if @export_versions
            versions = @query ? Version.where(id: @query_issues.map(&:fixed_version_id).uniq) : @project.versions
            versions.each { |version| write_version(xml, version) }
          end
          issues = (@query_issues || @project.issues.visible)
          nested_issues = determine_nesting issues, versions.try(:count)
          nested_issues.each_with_index { |issue, id| write_task(xml, issue, id) }

        }
        xml.Resources {
          xml.Resource {
            xml.UID 0
            xml.ID 0
            xml.Type 1
            xml.IsNull 0
          }
          resources.each_with_index do |resource, id|
            spent_time = TimeEntry.where(user_id: resource.id).inject(0){|sum, te| sum + te.hours }
            @uid += 1
            @resource_id_to_uid[resource.id] = @uid
            xml.Resource {
              xml.UID @uid
              xml.ID id.next
              xml.Name resource.login
              xml.Type 1
              xml.IsNull 0
              xml.MaxUnits 1.00
              xml.PeakUnits 1.00
              xml.IsEnterprise 1
              xml.CalendarUID @calendar_id_to_uid[resource.id]
              xml.ActualWork get_scorm_time(spent_time) unless spent_time.zero?
            }
          end
        }
        xml.Assignments {
		 
          source_issues = @query ? @query_issues : @project.issues
		  # If Resource not allocated then assign the task to default resource
          source_issues.select { |issue|  issue.leaf? }.each do |issue|  # issue.assigned_to_id? &&
		    hook_assignments = call_hook(:module_export_get_assignments, { :source_issues => issue})
			units = 1			
			hook_duration = call_hook(:module_export_get_duration, { :struct => issue})
			units = (issue.estimated_hours / hook_duration[0]) unless hook_duration.blank? || hook_duration[0].blank? || hook_duration[0] == 0
			if hook_assignments[0].blank?	
				@uid += 1
				write_assignment(xml, issue, @uid, issue.estimated_hours, @task_id_to_uid[issue.id], @resource_id_to_uid[issue.assigned_to_id], units)
			else 
				hook_assignments[0].each do |assignments|
					@uid = @uid + 1
					write_assignment(xml, issue, @uid, assignments.work, @task_id_to_uid[issue.id], @resource_id_to_uid[assignments.user_id], assignments.units)
				end 
			end
          end
        }
      }
    end

    filename = "#{@project.name}-#{Time.now.strftime("%Y-%m-%d-%H-%M")}.xml"
    return export.to_xml, filename
  end
  
  def write_assignment(xml, issue, uid, work, taskUid, resourceUid, units)
	xml.Assignment {
		unless !issue.leaf? #ignore_field?('estimated_hours', 'export') && 
			time = get_scorm_time(work)
			xml.Work time
			xml.RegularWork time
			xml.RemainingWork time
		end
		xml.UID uid
		xml.TaskUID taskUid
		xml.ResourceUID resourceUid #issue.assigned_to_id? ? @resource_id_to_uid[issue.assigned_to_id] : 0
		xml.PercentWorkComplete issue.done_ratio #unless ignore_field?('done_ratio', 'export')
		xml.Units units #1
		unless issue.total_spent_hours.zero?
			xml.TimephasedData {
				xml.Type 2
				xml.UID uid
				xml.Unit 2
				xml.Value get_scorm_time(issue.total_spent_hours)
				xml.Start (issue.start_date || issue.created_on).to_time.to_s(:ms_xml)
				xml.Finish ((issue.start_date || issue.created_on).to_time + (issue.total_spent_hours.to_i).hours).to_s(:ms_xml)
			}
		end
	}  
  end

  def determine_nesting(issues, versions_count)
    versions_count ||= 0
    nested_issues = []
    leveled_tasks = issues.sort_by(&:id).group_by(&:level)
    leveled_tasks.sort_by{ |key| key }.each do |level, grouped_issues|
      grouped_issues.each_with_index do |issue, index|
        outlinenumber = if issue.child?
          "#{nested_issues.detect{ |struct| struct.id == issue.parent_id }.try(:outlinenumber)}.#{leveled_tasks[level].index(issue).next}"
        else
          (leveled_tasks[level].index(issue).next + versions_count).to_s
        end
        nested_issues << ExportTask.new(issue, issue.level.next, outlinenumber)
      end
    end
	# To sort by outline number string (1.14, 1.9) then it will 1.14,1.9 . To correct tiss issue we add 100000 then change string which gives the expected sort 100000.100009, 100000.100014
    return nested_issues.sort_by!{ |t| t.outlinenumber.split('.').collect{ |n| n.to_i+100000 }.join('.') } #(&:outlinenumber)
  end

  # def get_priority_value(priority_name)
    # value = case priority_name
            # when 'Minimal' then 100
            # when 'Low' then 300
            # when 'Normal' then 500
            # when 'High' then 700
            # when 'Immediate' then 900
            # end
    # return value
  # end

  def get_scorm_time time
	# Return zero work as zero because milestone have 0 hours
    return 'PT0H0M0S' if time.nil? #|| time.zero?
    time = time.to_s.split('.')
    hours = time.first.to_i
    minutes = time.last.to_i == 0 ? 0 : (60 * "0.#{time.last}".to_f).to_i
    return "PT#{hours}H#{minutes}M0S"
  end

  def write_task(xml, struct, id)
	exAttrCfHash = getExtentedAttrFieldId
    @uid += 1
    @task_id_to_uid[struct.id] = @uid
    time = get_scorm_time(struct.estimated_hours)
	duration = time
	hook_constraint_type = call_hook(:module_export_get_constraint_type, { :struct => struct})
	hook_constraint_date = call_hook(:module_export_get_constraint_date, { :struct => struct})
	hook_task_type = call_hook(:module_export_get_task_type, { :struct => struct})
	hook_duration = call_hook(:module_export_get_duration, { :struct => struct})
	duration = get_scorm_time(hook_duration[0]) unless hook_duration.blank? || hook_duration[0].blank?
	
    xml.Task {
      xml.UID @uid
      xml.ID id.next
      xml.Name(struct.subject)
	  xml.Type hook_task_type.blank? || hook_task_type[0].blank? ? 0 : hook_task_type[0] 
      xml.Notes(struct.description) #unless ignore_field?('description', 'export')
      xml.Active 1
      xml.IsNull 0
      xml.CreateDate struct.created_on.to_s(:ms_xml)
      xml.HyperlinkAddress issue_url(struct.issue)
      xml.Priority struct.priority_id #(ignore_field?('priority', 'export') ? 500 : struct.priority_id)
      start_date = struct.issue.next_working_date(struct.start_date || struct.created_on.to_date)
	  hook_start = call_hook(:module_export_get_task_start_time, { :struct => struct})
	  start_date = hook_start[0] unless hook_start.blank? || hook_start[0].blank?
      xml.Start start_date.to_time.to_s(:ms_xml)
      finish_date = if struct.due_date
                      # if struct.issue.next_working_date(struct.due_date).day == start_date.day
                        # start_date.next
                      # else
                        # struct.issue.next_working_date(struct.due_date)
                      # end
					  struct.issue.next_working_date(struct.due_date)
                    else
                      start_date.next
                    end
	  hook_finish = call_hook(:module_export_get_task_finish_time, { :struct => struct})
	  finish_date = hook_finish[0] unless hook_finish.blank? || hook_finish[0].blank?
      xml.Finish finish_date.to_time.to_s(:ms_xml)
      xml.ManualStart start_date.to_time.to_s(:ms_xml)
      xml.ManualFinish finish_date.to_time.to_s(:ms_xml)
      xml.EarlyStart start_date.to_time.to_s(:ms_xml)
      xml.EarlyFinish finish_date.to_time.to_s(:ms_xml)
      xml.LateStart start_date.to_time.to_s(:ms_xml)
      xml.LateFinish finish_date.to_time.to_s(:ms_xml)
      xml.Work time
      xml.Duration duration #get_scorm_time(hook_duration[0])  #time
      #xml.ManualDuration time
      #xml.RemainingDuration time
      #xml.RemainingWork time
      #xml.DurationFormat 7
      xml.ActualWork get_scorm_time(struct.total_spent_hours)
      xml.Milestone 0
      xml.FixedCostAccrual 3
      xml.ConstraintType hook_constraint_type.blank? || hook_constraint_type[0].blank? ? 0 : hook_constraint_type[0] #2 Default is as soon as possible in projectlibre so change to zero
      xml.ConstraintDate hook_constraint_date.blank? || hook_constraint_date[0].blank? ? start_date.to_time.to_s(:ms_xml) : hook_constraint_date[0].to_time.to_s(:ms_xml)
      xml.IgnoreResourceCalendar 0
      parent = struct.leaf? ? 0 : 1
      xml.Summary(parent)
      #xml.Critical(parent)
      xml.Rollup(parent)
      #xml.Type(parent)
      if @export_versions && struct.fixed_version_id
        xml.PredecessorLink {
          xml.PredecessorUID @version_id_to_uid[struct.fixed_version_id]
          xml.CrossProject 0
        }
      end
      if struct.relations_to_ids.any?
        struct.relations.select { |ir| (ir.relation_type == 'precedes' && ir.issue_to_id == struct.id) || (ir.relation_type == 'follows' && ir.issue_from_id == struct.id) }.each do |relation|
          xml.PredecessorLink {
            xml.PredecessorUID @task_id_to_uid[relation.issue_from_id]
            if struct.project_id == relation.issue_from.project_id
              xml.CrossProject 0
            else
              xml.CrossProject 1
              xml.CrossProjectName relation.issue_from.project.name
            end
			
			relation_type = 1
			hook_relation_type = call_hook(:module_export_get_relation_type, { :relation => relation})
			relation_type = hook_relation_type[0] unless hook_relation_type.blank? || hook_relation_type[0].blank?
			xml.Type relation_type
			
			delay = relation.delay
			hook_delay = call_hook(:module_export_get_actual_delay, { :relation => relation})
			delay = hook_delay[0] unless hook_delay.blank? || hook_delay[0].blank?
			# -1 delay not export because of this condition. Start date and due date of predecessor are same when there is a -1 delay 
			if  delay != 0   #&& relation.issue_from.due_date != relation.issue_to.start_date #delay > 0
				xml.LinkLag (delay * 4800).to_i
				xml.LagFormat 7
			end
          }
        end
      end
      xml.ExtendedAttribute {
        xml.FieldID 188744000
        xml.Value struct.status.name
      }
      xml.ExtendedAttribute {
        xml.FieldID 188744001
        xml.Value struct.id
      }
      xml.ExtendedAttribute {
        xml.FieldID 188744002
        xml.Value struct.tracker.name
      }  
	  unless @settings['loader_percent_complete_attr'].blank?
		  xml.ExtendedAttribute {
			xml.FieldID exAttrCfHash[@settings['loader_percent_complete_attr']]
			xml.Value struct.done_ratio #unless ignore_field?('done_ratio', 'export')
		  }
	  end
	  getMappedAttrCF.each do |attr, cfId|
		unless struct.custom_field_value(cfId).blank?
			xml.ExtendedAttribute {
				xml.FieldID exAttrCfHash[attr]
				if attr.include? 'Date'
					xml.Value struct.custom_field_value(cfId).try(:to_time).try(:to_s, :ms_xml)
				else
					xml.Value struct.custom_field_value(cfId)
				end
			}
		end
	  end
      xml.WBS(struct.outlinenumber)
      xml.OutlineNumber struct.outlinenumber
      xml.OutlineLevel struct.outlinelevel
    }
  end

  def write_version(xml, version)
    xml.Task {
      @uid += 1
      @version_id_to_uid[version.id] = @uid
      xml.UID @uid
      xml.ID version.id
      xml.Name version.name
      xml.Notes version.description
      xml.CreateDate version.created_on.to_s(:ms_xml)
      if version.effective_date
        xml.Start version.effective_date.to_time.to_s(:ms_xml)
        xml.Finish version.effective_date.to_time.to_s(:ms_xml)
      end
      xml.Milestone 1
      xml.FixedCostAccrual 3
      xml.ConstraintType 4
      xml.ConstraintDate version.try(:effective_date).try(:to_time).try(:to_s, :ms_xml)
      xml.Summary 1
      xml.Critical 1
      xml.Rollup 1
      xml.Type 1
      xml.ExtendedAttribute {
        xml.FieldID 188744001
        xml.Value version.id
      }
      xml.WBS @uid
      xml.OutlineNumber @uid
      xml.OutlineLevel 1
    }
  end
  
  def addRevision
	revisionValue = " | Rev-"
	revisionValue += @project.custom_value_for(@settings['loader_project_cf']).value unless @settings['loader_project_cf'].blank?
	revisionValue
  end
end
