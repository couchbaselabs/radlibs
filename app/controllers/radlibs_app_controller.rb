class RadlibsAppController < ApplicationController
  include Term::ANSIColor
  include ModelGlobal

  def index
    #Analytics.retrieve_all_docs.each do |d|
    #  Rails.logger.debug(d.inspect)
    #end

    @activity = Analytics.get_latest_activity
    @logins = Analytics.get_latest_users_logged_in
    @signups = Analytics.get_latest_users_signed_up

  end

  def privacy_policy

  end

  def terms_and_conditions

  end

  def random_radlib
    if num_radlibs > 0
      @random_radlib_id = Random.rand(num_radlibs) + Analytics::RADLIB_COUNT_START + 1

      if session[:last_radlib_id_viewed] && num_radlibs > 1
        Rails.logger.debug("@random_radlib_id = #{@random_radlib_id}")
        Rails.logger.debug("session[:last_radlib_id_viewed] = #{session[:last_radlib_id_viewed]}")
        while @random_radlib_id.to_s.to_i == session[:last_radlib_id_viewed].to_s.to_i
          Rails.logger.debug("@random_radlib_id = #{@random_radlib_id}")
          @random_radlib_id = Random.rand(num_radlibs) + Analytics::RADLIB_COUNT_START + 1
        end
      end

      redirect_to "/r/#{@random_radlib_id}"
    end
  end

  def view_radlib
    radlib_id = params["radlib_id"]

    @user = (session && session[:user] ? session[:user] : nil)

    @radlib = find_radlib_by_radlib_id(radlib_id)


    if @radlib.nil?
      redirect_to radlib_not_found_path
    end

    session[:last_radlib_id_viewed] = radlib_id

    @radlib.radlib_text_array.process_words
    @word_stats = @radlib.radlib_text_array.word_stats

    Rails.logger.debug(@radlib.inspect)
    Rails.logger.debug(@radlib.class)
    Rails.logger.debug(@radlib.radlib_text_array.class)
    Rails.logger.debug(@radlib.radlib_text_array.inspect)

    @author = find_user_by_uid(@radlib.author_uid)

    # todo: change it so that it only happens once per session/per day
    if session["radlibs_viewed"]
      @radlib.increment_view_count unless session["radlibs_viewed"].include?(radlib_id.to_i)
      session["radlibs_viewed"].unshift(radlib_id.to_i)
    else
      session["radlibs_viewed"] = []
    end

    Analytics.analyze_most_popular_radlibs(@radlib)

  end

  # Placeholder page for when a Radlib isn't found, ie. mistyped url
  def radlib_not_found

  end

  def update_header_after_authentication

    if session && session[:user]
      render :partial => '/layouts/header', :locals => {:user => session[:user], :num_users => ApplicationController.num_users, :num_radlibs => ApplicationController.num_radlibs }
    end

  end

  def delete_all_docs_and_sessions
    DocumentStore.delete_all_documents!
    Analytics.new
    redirect_to logout_path
  end

end
