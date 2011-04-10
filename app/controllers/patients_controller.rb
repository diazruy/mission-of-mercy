class PatientsController < ApplicationController
  before_filter :login_required
  before_filter :admin_required, :only => [ :edit, :destroy ]
  before_filter :date_input
  before_filter :find_last_patient, :only => [:new]
  before_filter :set_current_tab
  
  def index
    if params[:commit] == "Clear"
      params[:chart_number] = nil
      params[:name] = nil
    end
  
    @patients = Patient.search(params[:chart_number], params[:name],params[:page])

    @area = params[:treatment_area_id]
    @area ||= session[:treatment_area_id] if session[:treatment_area_id]

    respond_to do |format|
      format.html # index.html.erb
      format.js { render :layout => false }
    end
  end

  def new
    @patient = Patient.new
    @patient.survey = Survey.new
  end

  def edit
    @patient = Patient.find(params[:id])
  end
  
  def print
    @patient = Patient.find(params[:id])

    render :action => "print", :layout => "print"
  end

  def create    
    @patient = Patient.new(params[:patient])
    
    add_procedures_to_patient(@patient)
    
    # Calculate Travel Time
    if params[:patient_travel_time_minutes].length > 0 && params[:patient_travel_time_minutes].match(/^\d+$/) != nil
      @patient.travel_time = params[:patient_travel_time_minutes].to_i
    end
    
    if params[:patient_travel_time_hours].length > 0 && params[:patient_travel_time_hours].match(/^\d+$/) != nil
      @patient.travel_time = 0 if @patient.travel_time.nil?
      @patient.travel_time += params[:patient_travel_time_hours].to_i * 60
    end
    
    if params[:patient][:pain_length_in_days].split(" ").length == 2
      number, type = params[:patient][:pain_length_in_days].split(" ")
      type = type.pluralize.downcase
    
      if type[/\Adays\Z|\Aweeks\Z|\Amonths\Z|\Ayears\Z/]
        @patient.pain_length_in_days = (number.to_f.send(type) / 1.day)
      else
        @patient.errors.add(:pain_length_in_days, "isn't valid. Try using days only.")
      end
    end
    
    if @patient.errors.empty? && @patient.save
      stats.patient_checked_in
      redirect_to new_patient_path(:last_patient_id =>  @patient.id)
    else
      @patient_travel_time_minutes = params[:patient_travel_time_minutes]
      @patient_travel_time_hours   = params[:patient_travel_time_hours]
    
      render :action => "new"
    end
  end
  
  def lookup_zip
    zip = Patient::Zipcode.find_by_zip(params[:zip])
    
    if zip
      zip = {
        :found => true,
        :zip   => zip.zip,
        :state => zip.state,
        :city  => zip.city
      }
    else
      zip = { :found => false }
    end
    
    respond_to do |format|
      format.json { render :json => zip.to_json }
    end
  end
  
  def export_to_dexis_file
    @patient = Patient.find(params[:patient_id])
    
    path = [app_config["dexis_path"],"passtodex",current_user.x_ray_station_id.to_s,".dat"].join()
    
    @patient.export_to_dexis(path)
    
    respond_to do |format|
      format.html do 
        @patient.flows.create(:area_id => ClinicArea::XRAY)
        @patient.update_attribute(:radiology, false)
        
        redirect_to treatment_area_patient_procedures_path(TreatmentArea.radiology, @patient.id)
      end
      format.js
    end
  end

  def update
    if params[:id] == nil
      params[:id] = params[:patient_id]
    end
    
    @patient = Patient.find(params[:id])
    
    if @patient.update_attributes(params[:patient])
      if params[:commit] == "Next"
        redirect_to(:controller => 'exit_surveys', :action => 'new', :id => @patient.id)
      else
        flash[:notice] = 'Patient was successfully updated.'
        
        redirect_to patients_path
      end
    else
      render :action => "edit"
    end
  end

  def destroy
    @patient = Patient.find(params[:id])
    @patient.destroy

    redirect_to(patients_url)
  end
  
  private
  
  def add_procedures_to_patient(patient)
    procedures = Procedure.find(:all, :conditions => {:auto_add => true})
    
    procedures.each do |p|
      patient.patient_procedures.build(:procedure_id => p.id)
    end
  end
  
  def date_input
    if params[:date_input]
      session[:date_input] = params[:date_input]
    end
    
    @date_input = session[:date_input] || 'select'
  end
  
  def find_last_patient
    if params[:last_patient_id] != nil
      @last_patient = Patient.find(params[:last_patient_id])
    end
  end
  
  def set_current_tab
    @current_tab = "patients" if current_user.user_type == UserType::ADMIN
  end
end
