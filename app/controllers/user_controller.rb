class UserController < ApplicationController
  include Term::ANSIColor
  include ModelGlobal
  include UserHelper

  # Create a New Radlib Page
  def create_radlib

    @user = nil
    if session && session[:user]
      @user = session[:user]
    end

  end

  # Save Created Radlib (via AJAX)
  def save_created_radlib

    radlib_title = params["radlib_title"]
    radlib_text_array = params["radlib_text_array"]
    original_text = params["original_text"]

    if session && session[:user]
      user = session[:user]

      # parse JSON submission to get proper formatting
      radlib_text_array = JSON.parse(radlib_text_array)

      # convert to RadlibTextArray object
      radlib_text_array = RadlibTextArray.new(radlib_text_array)

      radlib_text_array.clean_for_database

      # execute User Action (from User object)
      result = user.action_create_new_radlib(radlib_title, radlib_text_array, original_text)

      # if successful, add a new activity to the stream
      # activities: "created_radlib", "filled_in_radlib", "liked_fillin", "commented_on_fillin"
      Analytics.add_new_activity({ :uid => user.uid, :activity => "created_radlib", :radlib_id => result[:radlib_id] }) if result[:success]

    else
      result = { :success => false, :radlib_id => nil,  :error_code => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][0], :reason => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][1]}
    end

    respond_to do |format|
      format.json { render :json => result.to_json }
    end
  end




  # Save Filled Radlib (via AJAX)
  def save_filled_radlib
    radlib_id = params["radlib_id"].to_i
    radlib_text_array = params["radlib_filled"]

    if session && session[:user]
      user = session[:user]

      # Convert the Hash to an Array (see app/helpers UserHelper#array_from_hash), and convert the radlib_text_array to a RadlibTextArray Object
      radlib_text_array = RadlibTextArray.new(array_from_hash(radlib_text_array))

      # Clean up extra info from frontend hash not needed in database
      radlib_text_array.clean_for_database

      # Execute the Radlib Fillin User Action
      result = user.action_fill_in_radlib(radlib_id, radlib_text_array)

      # activities: "created_radlib", "filled_in_radlib", "liked_fillin", "commented_on_fillin"
      Analytics.add_new_activity({ :uid => user.uid, :activity => "filled_in_radlib", :radlib_id => result[:radlib_id] }) if result[:success]

    else
      result = {
          :success => false,
          :radlib_id => nil,
          :error_code => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][0],
          :reason => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][1]
      }
    end

    # return json response
    respond_to do |format|
      format.json { render :json => result.to_json }
    end
  end




  # Add a like to a filled-in Radlib (via AJAX)
  def like_radlib_fillin
    radlib_id = params["radlib_id"]
    radlib_fillin_id = params["radlib_fillin_id"]

    if session && session[:user]
      user = session[:user]
      result = user.action_like_radlib_fillin(radlib_id, radlib_fillin_id)

      if result[:success]
        # activities: "created_radlib", "filled_in_radlib", "liked_fillin", "commented_on_fillin"
        Analytics.add_new_activity({
                                       :uid => user.uid,
                                       :activity => "liked_fillin",
                                       :radlib_id => result[:radlib_id],
                                       :radlib_fillin_id => result[:radlib_fillin_id]
                                   })

        Analytics.increment_site_likes

      end

    else
      result = {
          :success => false,
          :radlib_id => nil,
          :error_code => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][0],
          :reason => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][1]
      }
    end

    respond_to do |format|
      format.json { render :json => result.to_json }
    end
  end


  def comment_on_radlib_fillin
    radlib_id = params["radlib_id"]
    radlib_fillin_id = params["radlib_fillin_id"]
    comment_text = params["comment_text"]

    if session && session[:user]
      user = session[:user]
      result = user.action_comment_on_fillin(radlib_id, radlib_fillin_id, comment_text)

      if result[:success]
        # activities: "created_radlib", "filled_in_radlib", "liked_fillin", "commented_on_fillin"
        Analytics.add_new_activity({
                                       :uid => user.uid,
                                       :activity => "commented_on_fillin",
                                       :radlib_id => result[:radlib_id],
                                       :radlib_fillin_id => result[:radlib_fillin_id]
                                   })

        Analytics.increment_site_comments
      end
    else
      result = {
          :success => false,
          :radlib_id => nil,
          :error_code => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][0],
          :reason => ErrorCodes::GLOBAL_ERRORS[:not_authenticated][1]
      }
    end

    respond_to do |format|
      format.json { render :json => result.to_json }
    end
  end

  # User Profile Page
  def profile
    uid = params[:uid]

    if @user = find_user_by_uid(uid)
      @radlibs_created = @user.radlibs_created(true)
    end


    redirect_to profile_not_found_path unless @user
  end

  # User Profile Not Found Page
  def profile_not_found

  end

  # Logout and reset session
  def logout
    session[:user] = nil
    session[:is_super_user] = nil
    session[:fb_access_token] = nil
    session[:user_expires_at] = nil
    session[:expires_string] = nil
    reset_session
    redirect_to '/'
  end

  def retrieve_facebook_friends

    if session && session[:user]
      user = session[:user]

      graph = Koala::Facebook::GraphAPI.new(session[:fb_access_token])
      friends = graph.get_connections(session[:fb_uid], "friends")
      session[:fb_friends] = friends

      user.facebook_friends = friends
    end

  end

  # Authenticate User
  def authenticate

    #DocumentStore.delete_all_documents!

    ## reset session on authenticate for security
    ## can't do this unless we can allow page-reloads
    # temp = session
    # reset_session
    # session.reverse_merge!(temp)



    session[:provider] = params["provider"]

    auth = request.env["omniauth.auth"]

    Rails.logger.debug(yellow("---------------------------------------------------------"))


    user = User.find_user_by_facebook_id(auth.uid)
    Rails.logger.debug(intense_green("User exists")) if user
    Rails.logger.debug(intense_red("User doesn't exist")) unless user

    unless user

      user_create = { :create => true,
                      :firstname => auth.info.first_name,
                      :lastname => auth.info.last_name,
                      :name => auth.info.name,
                      :nickname => auth.info.nickname,
                      :gender => auth.extra.raw_info.gender,
                      :email => auth.extra.raw_info.email,
                      :facebook_id => auth.uid,
                      :fb_img_square => "http://graph.facebook.com/#{auth.uid}/picture?type=square", # &return_ssl_resources=1
                      :fb_img_small => "http://graph.facebook.com/#{auth.uid}/picture?type=small", # &return_ssl_resources=1
                      :fb_img_normal => "http://graph.facebook.com/#{auth.uid}/picture?type=normal", # &return_ssl_resources=1
                      :fb_img_large => "http://graph.facebook.com/#{auth.uid}/picture?type=large", # &return_ssl_resources=1
                      :fb_access_token => auth.credentials.token,
                      :fb_token_expires => auth.credentials.expires_at
      }


      # retrieve User FB Object info from facebook

      graph = Koala::Facebook::GraphAPI.new(auth.credentials.token)
      fb_user_info = graph.get_object("me")

      session[:fb_uid] = auth.uid
      session[:fb_user_info] = fb_user_info
      session[:fb_access_token] = auth.credentials.token
      session[:fb_expires_at] = auth.credentials.expires_at
      session[:fb_expires_string] = Time.at(auth.credentials.expires_at)

      # we need at least one super user! so when creating user, check against the superuser set in config!
      if Yetting.super_user_fb_id.include?(auth.uid)
        user_create.merge!({:super_user => true})
      end

      # create new user and save to session
      user = User.new user_create
      session[:user] = user
      session[:is_super_user] = user.is_super_user?

      # track new user signups
      Analytics.add_user_signed_up(user.uid)

      Rails.logger.debug(user.inspect)

    else

      # track user logins
      Analytics.add_user_logged_in(user.uid)

      session[:user] = user
      session[:is_super_user] = user.is_super_user?
      session[:fb_uid] = user.facebook_id

      graph = Koala::Facebook::GraphAPI.new(user.fb_access_token)
      fb_user_info = graph.get_object("me")

      session[:fb_user_info] = fb_user_info
      session[:fb_access_token] = user.fb_access_token
      session[:fb_expires_at] = user.fb_token_expires
      session[:fb_expires_string] = Time.at(user.fb_token_expires)
    end

    Rails.logger.debug(yellow("---------------------------------------------------------"))


    # replace with ajax method to reduce lag time in login
    retrieve_facebook_friends

    user_docs = user.retrieve_all_docs
    Rails.logger.debug
    user_docs.each_pair do |key, doc|
      Rails.logger.debug(blue(key))
      Rails.logger.debug(reset(doc.inspect))
    end

    Rails.logger.debug(yellow("---------------------------------------------------------"))
    Rails.logger.debug(auth.inspect)
    Rails.logger.debug(yellow("---------------------------------------------------------"))
    #user = {:uid => auth["uid"], :firstname => auth["info"]["first_name"], :lastname => auth["info"]["last_name"], :token => auth["credentials"]["token"]}





    #session[:user] = user
    #Rails.logger.debug(@user.inspect)
    #redirect_to "/"
    render :text => "\n<script type=\"text/javascript\">\n\twindow.close();window.opener.user_authenticated = true;window.opener.after_authenticated();\n</script>"

  end
end
