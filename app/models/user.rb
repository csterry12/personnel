class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :encryptable, :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :trackable, :validatable, :confirmable

  # Setup accessible (or protected) attributes for your model
  #attr_accessible :email, :password, :password_confirmation, :identifier,
  #                :department_id, :active, :hired_at, :fired_at, :fired, :avatar

  belongs_to :department

  has_one :profile, :dependent => :destroy
  has_many :addresses, :dependent => :destroy
  has_one :contact, :dependent => :destroy
  has_many :schedule_cells, :dependent => :destroy
  has_many :events
  has_many :shifts
  has_many :late_comings
  has_many :norms
  has_many :user_permissions, :dependent => :destroy
  has_many :permissions, :through => :user_permissions, :uniq => true
  has_many :logs_entered, :class_name => 'Log', :as => :author
  has_many :logs, :as => :subject

  has_attached_file :avatar, :styles => {
      :large => "500x500>",
      :medium => {:geometry => "200x200>", :processors => [:cropper]},
      :thumb => {:geometry => "50x50>", :processors => [:cropper]}
  }
  attr_accessor :crop_x, :crop_y, :crop_w, :crop_h
  after_update :reprocess_avatar, :if => :cropping?

  after_create :create_internals

  delegate :birthdate, :to => :profile, :allow_nil => true
  delegate :cell1, :cell2, :cell3, :to => :contact, :allow_nil => true
  delegate :home_phone, :to => :contact, :allow_nil => false
  delegate :name, :to => :department, :prefix => true

  scope :with_data, includes(:profile, :addresses, :contact, :permissions)
  scope :identified, where('identifier IS NOT NULL')
  scope :active, where('active = 1')
  #scope :identifiers, order('identifier ASC').select('identifier')

  validates_presence_of :identifier, :if => :has_identifier?, :on => :update
  validates_uniqueness_of :identifier, :scope => :active, :if => :has_identifier?, :on => :update
  validates_confirmation_of :password
  validates_format_of :email,
                      :with => /\A([^@\s]+)@zone3000\.net\Z/i,
                      :message => 'Only Zone3000 local email is acceptable'

  before_validation :clean_unused_identifier

  def has_identifier?
    (department || Department.find(department_id)).has_identifier? if department_id
  end

  def full_name
    name = [profile.last_name, profile.first_name] * ' '
    name == ' ' ? email : name
  end

  def name
    full_name
  end

  def full_address
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
      shifts_count += cells * (shift.end - shift.start) /8.0
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

  def cropping?
    !crop_x.blank? && !crop_y.blank? && !crop_w.blank? && !crop_h.blank?
  end

  def avatar_geometry(style = :original)
    @geometry ||= {}
    @geometry[style] ||= Paperclip::Geometry.from_file(avatar.path(style))
  end

  private

  def create_internals
    create_profile
    create_contact
  end

  def self.search(params, page)
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
    conditions.push("`profiles`.last_name LIKE '%#{params[:full_name]}%'") unless params[:full_name].nil? || params[:full_name] == ""
    paginate :per_page => 15, :page => page,
             :conditions => conditions.join(' and '),
             :order => sort_by[params[:sort_by].to_sym]
  end

  def self.search_by_admin(params, page, admin_id)
    params[:sort_by] ||= :full_name
    sort_by = {
        :identifier => '`users`.identifier',
        :active => '`users`.active',
        :full_name => '`profiles`.last_name'
    }
    admin = Admin.find_by_id(admin_id)
    conditions = []
    conditions.push("department_id IN (#{admin.departments.map { |d| d.id }.join(',')})") unless admin.super_user?
    [:active, :department_id, :identifier].each do |field|
      conditions.push(field.to_s + " = '" + params[field] + "'") unless params[field].nil? || params[field] == ""
    end
    conditions.push("fired = 0") unless params[:employed].nil? || params[:employed] == ""
    conditions.push("`profiles`.last_name LIKE '%#{params[:full_name]}%'") unless params[:full_name].nil? || params[:full_name] == ""
    paginate :per_page => 15, :page => page,
             :conditions => conditions.join(' and '),
             :order => sort_by[params[:sort_by].to_sym]
  end

  def clean_unused_identifier
    if !self.department_id.nil?
      self.identifier = "" unless Department.find(self.department_id).has_identifier?
    end
    self.fired_at = "" unless self.fired
  end

  def self.selection(department_id)
    if department_id == 0
      with_data.order('`profiles`.last_name').active.map { |d| [d.full_name, d.id] }
    else
      order(:identifier).find_all_by_department_id_and_active(department_id, 1).map { |d| [d.identifier.to_s+ ' '+d.full_name, d.identifier] }
    end
  end

  def self.selection_by_admin(admin_id)
    admin = Admin.find_by_id(admin_id)
    return selection(0) if admin.super_user?
    departments = admin.departments.map{|d|d.id}
    users = []
    with_data.order('`profiles`.last_name').active.map do |d|
      users.push [d.full_name, d.id] if departments.include?(d.department_id)
    end
    users
  end

  def reprocess_avatar
    avatar.reprocess!
  end
end
