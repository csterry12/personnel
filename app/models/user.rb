#encoding=utf-8
class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :encryptable, :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :trackable, :validatable, :confirmable

  # Setup accessible (or protected) attributes for your model
  #attr_accessible :email, :password, :password_confirmation, :identifier,
  #                :department_id, :active, :hired_at, :fired_at, :fired, :avatar
  attr_accessor :birth_day_and_month
  belongs_to :department

  has_one :profile, :dependent => :destroy
  has_many :addresses, :dependent => :destroy
  has_one :contact, :dependent => :destroy
  belongs_to :department
  belongs_to :fire_reason
  has_many :schedule_cells, :dependent => :destroy
  has_many :events
  has_many :shifts
  has_many :late_comings
  has_many :norms
  has_many :user_permissions, :dependent => :destroy
  has_many :permissions, :through => :user_permissions, :uniq => true
  has_many :logs_entered, :class_name => 'Log', :as => :author
  has_many :logs, :as => :subject
  has_many :user_vehicles, dependent: :destroy
  has_many :vacation_requests, dependent: :destroy

  has_attached_file :avatar, :styles => {
      :large => "500x500>",
      :medium => {:geometry => "200x200", :processors => [:cropper]},
      :thumb => {:geometry => "50x50", :processors => [:cropper]}
  }
  attr_accessor :crop_x, :crop_y, :crop_w, :crop_h

  before_save :take_off_email

  before_validation :clean_unused_identifier
  before_validation {|u| (u.fired_at = nil; u.fire_reason_id = nil; u.fire_comment = nil) if u.fired_at.blank?}

  after_update :sync_with_forum, :send_hr_notification
  after_create :create_internals
  after_create :sync_with_forum

  delegate :birthdate, :to => :profile, :allow_nil => true
  delegate :cell1, :cell2, :cell3, :to => :contact, :allow_nil => true
  delegate :home_phone, :to => :contact, :allow_nil => false
  delegate :jabber, :to => :contact, :allow_nil => false
  delegate :name, :to => :department, :prefix => true

  scope :with_data, includes(:profile, :addresses, :contact, :permissions, :user_vehicles)
  scope :identified, where('identifier IS NOT NULL')
  scope :active, where('active = 1')
  scope :deliverable, where('deliverable = 1')
  #scope :identifiers, order('identifier ASC').select('identifier')

  validates_presence_of :department_id
  validates_presence_of :identifier, :if => :has_identifier?
  validates_presence_of :fire_reason_id, if: Proc.new {|u| u.fired_at}
  validates_presence_of :fire_comment, if: Proc.new {|u| u.fired_at}
  validates_uniqueness_of :identifier, :scope => :active, :if => :has_identifier?
  validates_confirmation_of :password
  validates_format_of :email,
                      :with => /\A([^@\s]+)@zone3000\.net\Z/i
  validates_attachment_content_type :avatar, :content_type => ['image/jpeg', 'image/png', 'image/gif']


  def has_identifier?
    return false if !active
    (department || Department.find(department_id)).has_identifier? if department_id
  end

  def full_name
    name = [profile.last_name, profile.first_name] * ' ' rescue ' '
    name == ' ' ? email : name
  end

  def name
    full_name
  end

  def full_address
    return if !department.show_address?
    @address = addresses.order('addresses.primary DESC').first
    return '' if @address.nil?
    attributes = %w(street build porch nos)
    separators = [', ', ' || ', ' / ']
    return nil if attributes.any? { |a| @address[a].nil? || @address[a] == '' }
    attributes.map { |a| @address[a] }.zip(separators).flatten.compact.join
  end

  def full_address_admin
    @address = addresses.order('addresses.primary DESC').first
    return '' if @address.nil?
    attributes = %w(street build porch nos room)
    separators = [', ', ' || ', ' / ', ', кв.']
    return nil if attributes.any? { |a| @address[a].nil? || @address[a] == '' }
    attributes.map { |a| @address[a] }.zip(separators).flatten.compact.join
  end

  def work_shifts_count(template_id)
    shifts_count = 0
    shifts = ScheduleShift.where('number < 10').find_all_by_schedule_template_id template_id
    shifts.each do |shift|
      cells = ScheduleCell.where(:schedule_shift_id => shift.id).where(:user_id => self.identifier).count(:all)
      shift_duration = shift.end - shift.start
      shift_duration += 24 if shift_duration < 0
      shifts_count += cells * shift_duration /8.0
    end
    shifts_count
  end

  def work_nights_count(template_id)
    shifts_count = 0
    shifts = ScheduleShift.where(:start => 0).where('number < 10').find_all_by_schedule_template_id template_id
    shifts.each do |shift|
      cells = ScheduleCell.where(:schedule_shift_id => shift.id).where(:user_id => self.identifier).count(:all)
      shifts_count += cells
    end
    shifts_count
  end

  def day_off_count(template_id)
    shifts_count = 0
    shifts = ScheduleShift.where(:number => 10).find_all_by_schedule_template_id template_id
    shifts.each do |shift|
      cells = ScheduleCell.where(:schedule_shift_id => shift.id).where(:user_id => self.identifier).count(:all)
      shifts_count += cells
    end
    shifts_count
  end

  #def norma(template_id)
  #  shifts_count = 0
  #  shifts = ScheduleShift.where(:number => 10).find_all_by_schedule_template_id template_id
  #  shifts.each do |shift|
  #    cells = ScheduleCell.where(:schedule_shift_id => shift.id).where(:user_id => self.identifier).count(:all)
  #    shifts_count += cells
  #  end
  #  shifts_count
  #end

  def crop_avatar(args)
    self.crop_x = args["crop_x"]
    self.crop_y = args["crop_y"]
    self.crop_w = args["crop_w"]
    self.crop_h = args["crop_h"]
    avatar.reprocess!
  end

  def cropping?
    !crop_x.blank? && !crop_y.blank? && !crop_w.blank? && !crop_h.blank?
  end

  def avatar_geometry(style = :original)
    @geometry ||= {}
    @geometry[style] ||= Paperclip::Geometry.from_file(avatar.path(style))
  end

  def self.identifier_selection(current_identifier)
    a = current_identifier.nil? ? [] : [current_identifier]
    s = order(:identifier).where('identifier IS NOT NULL AND active = 1').group(:identifier).all.map(&:identifier)
    ((1..s.last+20).to_a - s + a).sort.each do |d|
      [d, d]
    end
  end

  def experience

  end

  def active_for_authentication?
    super && !fired
  end

  def inactive_message
    if fired
      :locked
    else
      super
    end

  end

  def sync_with_forum
    return if email == 'admin@zone3000.net'
    forum_member = SmfMember.find_or_create_by_member_name(email.gsub(/@zone3000.net/, ''))
    forum_member.id_group = SmfMembergroup.find_or_create_by_group_name(department.name).id_group if department
    forum_member.real_name = full_name
    forum_member.email_address = email
    forum_member.birthdate = birthdate
    forum_member.avatar = 'http://staff.zone3000.net'+avatar.url(:thumb) if avatar?
    forum_member.date_registered = hired_at.to_time.to_i if hired_at?
    forum_member.passwd = Digest::SHA1.hexdigest(forum_member.member_name.downcase+password) unless password.nil?
    forum_member.password_salt = 'xxxx' unless password.nil?
    forum_member.save
  end

  def extended_permissions_by_section(section_name)
    return nil if extended_permissions.blank?
    extended_permissions.split("\r\n").each do |section|
      name, depts = section.split(":").map(&:strip)
      return Department.all.map(&:id) if depts == "all" and name == section_name
      return depts.split(",").map(&:to_i) if name == section_name rescue nil
    end
    nil
  end

  def self.birthdays_selection
    [1, 3, 6, 12].each do |d|
      [d, d]
    end
  end

  private

  def create_internals
    create_profile
    create_contact
    self.department_id ||= Department.find_or_create_by_name('General').id
    self.deliverable = (department.has_identifier? and department.show_address?)
    save

    unless self.active?
      # send notification to admin
      department = Department.find(self.department_id)
      admins = department.admins.map(&:email)
      message = UserAuth.send_user_created(self, admins)
      message.deliver
    end
  end

  def self.search(params)
    params[:sort_by] ||= :full_name
    sort_by = {
        :identifier => '`users`.identifier',
        :active => '`users`.active',
        :full_name => '`profiles`.last_name'
    }

    conditions = []

    [:active, :department_id, :identifier].each do |field|
      conditions.push(field.to_s + " = '" + params[field] + "'") unless params[field].nil? || params[field] == ""
    end
    conditions.push("(`profiles`.last_name LIKE '%#{params[:full_name]}%' OR `profiles`.first_name LIKE '%#{params[:full_name]}%')") unless params[:full_name].nil? || params[:full_name] == ""
    paginate :per_page => [params[:per_page].to_i, 5].max, :page => params[:page],
             :conditions => conditions.join(' and '),
             :order => "#{sort_by[params[:sort_by].to_sym]} #{params[:sort_order]}"
  end

  def self.search_by_admin(params, admin_id)
    params[:sort_by] ||= :full_name
    sort_by = {
        :identifier => '`users`.identifier',
        :active => '`users`.active',
        :full_name => '`profiles`.last_name',
        :department_id => 'department_id'
    }
    admin = Admin.find_by_id(admin_id)
    conditions = []
    conditions.push("department_id IN (#{admin.departments.map { |d| d.id }.join(',')})") unless admin.super_user?
    [:active, :department_id, :identifier].each do |field|
      conditions.push(field.to_s + " = '" + params[field] + "'") unless params[field].blank?
    end
    conditions.push("fired = 0") unless params[:employed].nil? || params[:employed] == ""
    conditions.push("(`profiles`.last_name LIKE '%#{params[:full_name]}%' OR `profiles`.first_name LIKE '%#{params[:full_name]}%')") unless params[:full_name].blank?
    conditions.push("`user_vehicles`.`vehicle_type` = #{params[:vehicle_type]}") unless params[:vehicle_type].blank?
    conditions.push("`user_vehicles`.`reg_number` LIKE '%#{params[:reg_number]}%'") unless params[:reg_number].blank?
    paginate :per_page => [params[:per_page].to_i, 5].max, :page => params[:page],
             :conditions => conditions.join(' and '),
             :order => "#{sort_by[params[:sort_by].to_sym]} #{params[:sort_order]}"
  end

  def clean_unused_identifier
    if !self.department_id.nil?
      self.identifier = "" unless Department.find(self.department_id).has_identifier?
    end
    #self.fired_at = "" unless self.fired  # set automaticly when all permissions unset
  end

  def self.selection(department_id)
    if department_id == 0
      includes(:profile).order('`profiles`.last_name').active.map { |d| [d.full_name, d.id] }
    else
      includes(:profile).order(:identifier).find_all_by_department_id_and_active(department_id, 1).map { |d| [d.identifier.to_s+ ' '+d.full_name, d.identifier] }
    end
  end

  def self.selection_by_admin(admin_id, department_id = nil)
    admin = Admin.find_by_id(admin_id)
    if admin.super_user?
      if department_id.to_i == 0
        return includes(:profile).order('`profiles`.last_name').active.map { |d| [d.full_name, d.id] }
      else
        return includes(:profile).order(:identifier).find_all_by_department_id_and_active(department_id, 1).map { |d| [d.full_name, d.id] }
      end
    end
    departments = department_id.to_i == 0 ? admin.departments.map { |d| d.id } : [department_id.to_i]
    users = []
    includes(:profile).order('`profiles`.last_name').active.map do |d|
      users.push [d.full_name, d.id] if departments.include?(d.department_id)
    end
    users
  end

  def self.selection_by_admin_list(admin_id, department_id = nil)
    admin = Admin.find_by_id(admin_id)
    if admin.super_user?
      if department_id.to_i == 0
        return includes(:profile).order('`profiles`.last_name').active.map { |d| [d.full_name, d.id] }
      else
        return includes(:profile).order('`profiles`.last_name').find_all_by_department_id_and_active(department_id, 1).map { |d| [d.full_name, d.id] }
      end
    end
    departments = department_id.to_i == 0 ? admin.departments.map { |d| d.id } : [department_id.to_i]
    users = []
    includes(:profile).order('`profiles`.last_name').active.map do |d|
      users.push [d.full_name, d.id] if departments.include?(d.department_id)
    end
    users
  end

  def self.selection_by_team_lead(user_id)
    user = User.find_by_id(user_id)
    return false unless user.team_lead?
    users = []
    includes(:profile).order('`profiles`.last_name').active.map do |d|
      users.push [d.full_name, d.id] if user.department_id == d.department_id
    end
    users
  end

  def self.t_shirts(admin_id)
    model_query = Profile.select('`profiles`.t_shirt_size, `profiles`.level, `departments`.name, COUNT(`users`.id) as total')
    model_query = model_query.where("`profiles`.t_shirt_size != ''")
    model_query = model_query.joins('JOIN `users` ON `profiles`.user_id = `users`.id')
    model_query = model_query.joins('JOIN `departments` ON `users`.department_id = `departments`.id')
    if admin_id != 0
      admin = Admin.find_by_id(admin_id)
      model_query = model_query.where("`users`.department_id IN (#{admin.departments.map { |d| d.id }.join(',')})") unless admin.super_user?
    end
    model_query = model_query.group('`departments`.name, `profiles`.t_shirt_size, `profiles`.level')
    model_query = model_query.order('`departments`.name', '`profiles`.t_shirt_size')
    model_query.all
  end

  def send_hr_notification
    if active_changed? and active?
      message = HrNotification.send_user_activated(self)
      message.deliver
    end
    if fired_at? and fired_at_changed?
      message = HrNotification.send_user_fired(self)
      message.deliver
    end
  end

  def take_off_email
    if active_changed?
      if active?
        self.email = self.email.gsub(/^\d{4}\-\d{2}\-\d{2}\-/, '')
      else
        self.email = "#{Date.current.to_formatted_s(:db)}-#{self.email}"
      end
    end
  end

end
