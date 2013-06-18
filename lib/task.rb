class Task < Struct.new(:assigned_to,
                        :category,
                        :code,
                        :delays,
                        :duration,
                        :finish,
                        :issue,
                        :level,
                        :milestone,
                        :notes,
                        :outlinenumber,
                        :outlinelevel,
                        :outnum,
                        :parent_id,
                        :percentcomplete,
                        :predecessors,
                        :priority,
                        :start,
                        :tid,
                        :title,
                        :tracker_id,
                        :uid)
end