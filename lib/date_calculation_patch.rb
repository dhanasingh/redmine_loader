module DateCalculationPatch
	def self.included(base)
        base.class_eval do
			# Give the working days in negative if to_date earlier than from_date
			def working_days(from, to)
				days = (to - from).to_i
				# if days > 0
				  weeks = days / 7
				  result = weeks * (7 - non_working_week_days.size)
				  days_left = days - weeks * 7
				  start_cwday = from.cwday
				  days_left.times do |i|
					unless non_working_week_days.include?(((start_cwday + i - 1) % 7) + 1)
					  result += 1
					end
				  end
				  result
				# else
				  # 0
				# end
			end

			  # Adds working days to the given date
			  # Patch for add working days in negative
			def add_working_days(date, working_days)
				# if working_days > 0
				  weeks = working_days / (7 - non_working_week_days.size)
				  result = weeks * 7
				  days_left = working_days - weeks * (7 - non_working_week_days.size)
				  cwday = date.cwday
				  while days_left > 0
					cwday += 1
					unless non_working_week_days.include?(((cwday - 1) % 7) + 1)
					  days_left -= 1
					end
					result += 1
				  end
				  next_working_date(date + result)
				# else
				  # date
				# end
			end
		end
	end
end
