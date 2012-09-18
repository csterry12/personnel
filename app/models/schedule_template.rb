class ScheduleTemplate < ActiveRecord::Base
  belongs_to :department
  has_many :schedule_shifts, :dependent => :destroy

  def check_day(day)
    total_normal = 0
    @users = User.find_all_by_department_id_and_active self.department_id, 1
    @users.each do |user|
      total_normal += user.identifier * 8.0
    end
    total_fact = 0

    shifts = ScheduleShift.find_all_by_schedule_template_id self.id
    shifts.each do |shift|
      hours = shift.end - shift.start
      cells = ScheduleCell.find_all_by_schedule_shift_id_and_day(shift.id, day)
      unless cells.nil?
        cells.each do |cell|
          total_fact += cell.user_id * hours unless cell.user_id.nil?
        end
      end
    end
    total_normal <=> total_fact
  end

  def check_day_detailed(day)
    total_normal = 8.0
    missed = []
    extra = []
    @users = User.find_all_by_department_id_and_active self.department_id, 1
    @shifts = ScheduleShift.find_all_by_schedule_template_id self.id
    @users.each do |user|
      total_fact = 0
      @shifts.each do |shift|
        hours = shift.end - shift.start
        cells = ScheduleCell.find_all_by_schedule_shift_id_and_day(shift.id, day)
        unless cells.nil?
          cells.each do |cell|
            total_fact += hours if cell.user_id == user.identifier
          end
        end
      end
      ap total_fact
      missed << user.identifier if total_fact < total_normal
      extra << user.identifier if total_fact > total_normal
    end
    [missed.sort, extra.sort]
  end
end
