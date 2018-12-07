require 'redmine'

require_dependency 'string'
require_dependency 'element'
require_dependency 'views_issues_index_bottom_hook'

ActionDispatch::Callbacks.to_prepare do
  SettingsHelper.__send__(:include, SettingsHelperPatch)
  Mailer.__send__(:include, LoaderMailer)
  Issue.__send__(:include, IssuePatch)
  IssueRelation.__send__(:include, IssueRelationPatch)
  Redmine::NestedSet::Traversing.__send__(:include, TraversingPatch)
  Redmine::Views::OtherFormatsBuilder.__send__(:include, LoaderOtherFormatsBuilder)
  Redmine::Utils::DateCalculation.__send__(:include, DateCalculationPatch)
end

Redmine::Plugin.register :redmine_loader do

  author 'Simon Stearn, Andrew Hodgkinsons'

  desc = 'MS Project/Redmine sync plugin Build13'
  name desc
  description desc

  version '0.4'

  requires_redmine version_or_higher: '2.3.0'

  default_tracker_alias = 'Tracker'

  settings default: {
    export: {
	    sync_versions: false,
      ignore_fields: {
        description: false,
        priority: false,
        done_ratio: false,
        estimated_hours: false,
        spent_hours: false
      }
    },
    import: {
	    is_private_by_default: false,
	    instant_import_tasks: 10,
	    sync_versions: false,
	    tracker_alias: default_tracker_alias,
      redmine_id_alias: 'RID',
      ignore_fields: {
        description: false,
        priority: false,
        done_ratio: false,
        estimated_hours: false,
        spent_hours: false
      }
    },
  }, partial: 'settings/loader_settings'


  project_module :project_xml_importer do
    permission :import_issues_from_xml, loader: [:new, :create]
    permission :export_issues_to_xml, loader: :export
  end

  menu :project_menu, :loader, { controller: :loader, action: :new },
    caption: :menu_caption, param: :project_id
	

  Time::DATE_FORMATS.merge!(
    ms_xml: lambda{ |time| time.strftime("%Y-%m-%dT%H:%M:%S") }
  )
end
