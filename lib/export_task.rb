class ExportTask < Struct.new(:issue, :outlinelevel, :outlinenumber, :uid)

  def method_missing method, options=nil
	unless options.blank?
		issue.send method, options  if issue.respond_to? method, options 
	else
		issue.send method  if issue.respond_to? method
	end
  end
end
