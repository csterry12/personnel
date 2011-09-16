class Admin::EventsController < ApplicationController
  before_filter :authenticate_admin!
  before_filter :check_permissions, :except => :delivery
  layout 'admin'

  def check_permissions
    redirect_to delivery_admin_users_path unless current_admin.super_user? || !current_admin.departments.empty?
  end

  def index
    params[:date_from] = (DateTime.current - 2.hour).to_formatted_s(:date_and_time)  if !params[:date_from]
    params[:date_to] = DateTime.current.to_formatted_s(:date_and_time)  if !params[:date_to]


    @events = Event.joins('JOIN users ON events.user_id = users.id').search(params, params[:page], current_admin.id)

    respond_to do |format|
      format.html # index.html.erb
      format.xml { render :xml => @events }
    end
  end

  def show

  end

  def new
    @event = Event.new
    render :layout => false
  end

  def edit
    @event = Event.find(params[:id])
    render :layout => false
  end

  def create
    @event = Event.new(params[:event])
    @event.ip_address = Event.ip2int(request.remote_ip)

    if @event.save
      render(:update) do |page|
        page["#overlay"].dialog("close")
        page.call 'app.reload'
      end
    else
      message = '<p>' + @event.errors.full_messages.join('</p><p>') + '</p>'
      render(:update) do |page|
        page['#event_flash'].parents(0).show
        page['#event_flash'].html message
      end
    end

  end

  def update
    @event = Event.find(params[:id])
    @event.ip_address = Event.ip2int(request.remote_ip)

    if @event.update_attributes(params[:event])
      render(:update) do |page|
        page["#overlay"].dialog("close")
        page.call 'app.reload'
      end
    else
      message = '<p>' + @event.errors.full_messages.join('</p><p>') + '</p>'
      render(:update) do |page|
        page['#event_flash'].parents(0).show
        page['#event_flash'].html message
      end
    end
  end

  def destroy
    @event = Event.find(params[:id])
    @event.destroy

    respond_to do |format|
      format.html { redirect_to :back }
      format.xml { head :ok }
    end
  end
end