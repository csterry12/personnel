class Event < ActiveRecord::Base
  belongs_to :category
  belongs_to :user
  validates_presence_of :description, :user_id, :category_id
  delegate :name, :to => :category, :prefix => true
  delegate :displayed, :to => :category, :prefix => true
  delegate :full_name, :to => :user, :prefix => true

  scope :identified, where('identifier IS NOT NULL')

  def self.search(params, page)
    params[:sort_by] ||= :eventtime

    conditions = []
    conditions.push("user_id = '" + params[:user_id] + "'") unless params[:user_id].nil? || params[:user_id] == ""
    conditions.push("eventtime >= '" + params[:date_from].to_s + "'") unless params[:date_from].nil? || params[:date_from] == "" || params[:date_from_check].nil?
    conditions.push("eventtime <= '" + params[:date_to].to_s + "'") unless params[:date_to].nil? || params[:date_to] == "" || params[:date_to_check].nil?

    paginate :per_page => 15, :page => page,
             :conditions => conditions.join(' and '),
             :order => params[:sort_by]
  end

  def self.login(user_id, time)
    @category = Category.find_or_create_by_name('Login')
    @event = Event.create(:user_id => user_id, :category_id => @category.id, :eventtime => time, :description => '-')
    @event.save
    @event.id
  end

  def self.logout(user_id, time)
    @category = Category.find_or_create_by_name('Logout')
    @event = Event.create(:user_id => user_id, :category_id => @category.id, :eventtime => time, :description => '-')
    @event.save
    @event.id
  end

end
