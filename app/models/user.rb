# Author:: Couchbase <info@couchbase.com>
# Copyright:: 2012 Couchbase, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
### The User class contains all the actions that users take on the system, very User centric
###
### Note: for the document keys starting with num_ we employed metaprogramming to create methods
###   for get and increment, see create_doc_keys() to see how that was done, we did this because there were
###   so many keys to keep the file size small and reduce typing errors
###
class User < RadlibsBase
  include DocumentStore
  include ModelValidations
  include ModelGlobal
  include ErrorCodes

  attr_accessor :uid, :firstname, :lastname, :name, :nickname, :gender, :email, :facebook_id,
                :fb_img_square, :fb_img_small, :fb_img_normal, :fb_img_large, :fb_friends,
                :fb_access_token, :fb_token_expires, :super_user


  def initialize(attr = {})
    @super_user = false
    attr = Map.new(attr)
    super

    # load passed in parameter attributes
    load_parameter_attributes attr

    # Typically in Couchbase you want to create document and then modify instead of waiting for save method at the end
    # we pass in :create => true to create this user, then we can modify the user later
    # We'll make sure it's valid by checking to see if the user already exists
    if attr.has_key_and_value?(:create)
      raise "trying to create user -- user exists already (via facebook_id)" if @facebook_id && User.find_user_by_facebook_id(@facebook_id)
      raise "trying to create user -- user exists already (via email)" if @email && User.find_user_by_email(@email)
      raise "trying to create user -- user exists already (via uid)" if @uid && User.find_user_by_uid(@uid)
      create_new
    end

    # Either we are creating or retrieving a user, if we are retrieving, we need at least one of three possible user
    # identifiers to be passed in as an attribute/parameter
    if attr.has_key_and_value?(:retrieve)
      unless attr.has_key_and_value?(:facebook_id) || attr.has_key_and_value?(:email) || attr.has_key_and_value?(:uid)
        raise "trying to retrieve user -- requires facebook_id, email or uid"
      end
      load_persisted

    end

    self
  end


  #### PRIVATE/DEFAULT/OVERLOADED METHODS

  private

  def create_doc_keys
    unless @doc_keys_setup
      @docs = {}

      @docs[:user] = "u::#{uid}"

      @docs[:facebook_ref] = "fb::#{@facebook_id}"
      @docs[:email_ref] = "email::#{@email.downcase}"

      @docs[:radlibs_created] = "u::#{uid}::radlibs_created"
      @docs[:radlibs_filled]  = "u::#{uid}::radlibs_filled"

      @docs[:num_site_visits]  = "u::#{uid}::site_visits"
      @docs[:num_radlibs_created] = "u::#{uid}::radlibs_created_count"
      @docs[:num_radlibs_filled_by_me] = "u::#{uid}::radlibs_filled_by_me_count"
      @docs[:num_radlibs_filled_by_others] = "u::#{uid}::radlibs_filled_by_others_count"
      @docs[:num_comments_made]  = "u::#{uid}::comments_made_count"
      @docs[:num_comments_received] = "u::#{uid}::comments_received_count"
      @docs[:num_likes_made]  = "u::#{uid}::likes_made_count"
      @docs[:num_likes_received] = "u::#{uid}::likes_received_count"
      @docs[:num_radlib_views_made]  = "u::#{uid}::views_made_count"
      @docs[:num_radlib_views_received]  = "u::#{uid}::views_received_count"

      @docs[:facebook_friends] = "u::#{uid}::facebook_friends"
      @docs[:num_facebook_friends] = "u::#{uid}::num_facebook_friends"

      @doc_keys_setup = true


      # Since we have a lot of stats keys, use some metaprogramming to define the methods for get and increment
      @docs.each do |method,v|

        if method.to_s.starts_with?("num_")

          # create get method for document symbol that starts with num_
          # i.e. def num_site_views
          self.class.send(:define_method, method) do
            get_document(@docs[method])
          end

          # create increment method for document symbol that starts with num_
          # i.e. def increment_site_views
          self.class.send(:define_method, method.to_s.gsub("num", "increment").to_sym) do
            increase_atomic_count(@docs[method])
          end


        end
      end


    end
  end

  def create_default_docs
    create_doc_keys unless doc_keys_setup

    if @uid && @facebook_id

      default_user_doc = { :type => "user",
                           :uid => @uid,
                           :firstname => @firstname,
                           :lastname => @lastname,
                           :name => @name,
                           :email => @email,
                           :facebook_id => @facebook_id,
                           :nickname => @nickname,
                           :gender => @gender,
                           :fb_img_square => @fb_img_square,
                           :fb_img_small => @fb_img_small,
                           :fb_img_normal => @fb_img_normal,
                           :fb_img_large => @fb_img_large,
                           :fb_access_token => @fb_access_token,
                           :fb_token_expires => fb_token_expires,
                           :super_user => @super_user}

      initialize_document(@docs[:user], default_user_doc)

      # initialize if we have a facebookID and userID, simple for now
      initialize_document(@docs[:facebook_ref], @uid)
      initialize_document(@docs[:email_ref], @uid)

      default_radlibs_arrays = { :radlibs => [] }
      initialize_document(@docs[:radlibs_created], default_radlibs_arrays)
      initialize_document(@docs[:radlibs_filled], default_radlibs_arrays)

      ### STATS, initialize all docs that start with num_ with a count of 0
      @docs.each do |doc_key,v|
        if doc_key.to_s.starts_with?("num_")
          initialize_document(@docs[doc_key], 0)
        end
      end

      initialize_document(@docs[:facebook_friends], { :friends => [] })
    end
  end

  # create a new user and associated documents
  def create_new
    @uid = get_new_uid
    create_default_docs
    if @super_user
      add_super_user(@uid)
    end
  end

  def load_persisted
    if @facebook_id
      @uid = get_document("fb::#{@facebook_id}")
    elsif @email
      @uid = get_document("email::#{@email}")
    end
    load_parameter_attributes get_document("u::#{@uid}")
    create_default_docs
  end


  #### PROPERTIES & PROPERTY OVERLOADS
  public

  def radlibs_created(get_radlib_objects = false)
    if get_radlib_objects

      doc = get_document(@docs[:radlibs_created])
      create_default_docs unless doc

      radlibs = []

      doc[:radlibs].each do |r|
        radlib = find_radlib_by_radlib_id(r)
        radlibs.push(radlib) if radlib
      end

      return nil if radlibs.empty?
      radlibs

    else
      doc = get_document(@docs[:radlibs_created])
      create_default_docs unless doc
      doc[:radlibs]
    end

  end

  def radlibs_filled
    doc = get_document(@docs[:radlibs_filled])
    create_default_docs unless doc
    doc[:radlibs]
  end


  ### STATS Reporting --------------------------------------------------------------

  ### REPLACED BY METAPROGRAMMING, see create_doc_keys()
  #def radlibs_filled_by_me
  #  atomic_count = get_document(@docs[:num_radlibs_filled_by_me])
  #  create_default_docs unless atomic_count
  #  atomic_count
  #end


  ### STATS Tracking --------------------------------------------------------------

  ### REPLACED BY METAPROGRAMMING, see create_doc_keys()
  #def increment_radlibs_filled_by_me
  #  atomic_count = get_document(@docs[:num_radlibs_filled_by_me])
  #  create_default_docs unless atomic_count
  #  increase_atomic_count(@docs[:num_radlibs_filled_by_me])
  #end



  def is_super_user?
    @super_user
  end

  def is_superuser?
    @super_user
  end

  def facebook_friends
    doc = get_document(@docs[:facebook_friends])
    doc[:friends]
  end

  def facebook_friends=(friend_hash)
    doc = get_document(@docs[:facebook_friends])

    Analytics.decrement_facebook_friends(doc[:friends].size)

    doc[:friends] = friend_hash

    Rails.logger.debug(doc[:friends].size)
    Analytics.increment_facebook_friends(doc[:friends].size)

    replace_document(@docs[:facebook_friends], doc)
    force_set_document(@docs[:num_facebook_friends], doc[:friends].size)
  end






  #### USER ACTIONS - the things the User can DO

  def action_create_new_radlib(radlib_title, radlib_text_array, original_sentences)

    if validate_create_new_radlib(radlib_title, radlib_text_array)

      new_radlib = RadlibStory.new ({ :create => true,
                                      :radlib_title => radlib_title,
                                      :radlib_text_array => radlib_text_array,
                                      :author_uid => @uid,
                                      :original_sentences => original_sentences})

      add_radlib_to_created(new_radlib.radlib_id)

      # Run Analytics on new data
      Analytics.analyze_user(self)

      result = { :success => true,
                 :radlib_id => new_radlib.radlib_id,
                 :radlib_url => Yetting.domain + "r/#{new_radlib.radlib_id}",
                 :error_name => nil,
                 :error_code => nil,
                 :reason => nil,
                 :help_text => nil,
                 :backtrace => nil}
    end

  rescue Exception => e
    raise e unless RADLIB_CREATE_ERRORS.has_key?(e.message.to_sym)
    result = {
        :success => false,
        :radlib_id => nil,
        :radlib_url => nil,
        :error_name => e.message.to_s,
        :error_code => ErrorCodes::RADLIB_CREATE_ERRORS[e.message.to_sym][0],
        :reason => ErrorCodes::RADLIB_CREATE_ERRORS[e.message.to_sym][1],
        :help_text => ErrorCodes::RADLIB_CREATE_ERRORS[e.message.to_sym][2],
        :backtrace => e.backtrace.inspect
    }
  end

  def action_fill_in_radlib(radlib_id, radlib_text_array)

    if validate_fill_in_radlib(radlib_id, radlib_text_array)
      radlib = find_radlib_by_radlib_id(radlib_id)
      radlib_fillin = radlib.add_fillin({:uid => @uid, :radlib_text_array => radlib_text_array})

      # increase num_radlibs_filled
      increment_radlibs_filled_by_me

      # get the author, and increase num_radlibs_filled_by_others
      author = find_user_by_uid(radlib.author_uid)
      author.increment_radlibs_filled_by_others

      # Run Analytics on new data
      Analytics.analyze_user(self)
      Analytics.analyze_user(author)

      result = {
          :success => true,
          :radlib_id => radlib_id,
          :radlib_fillin_id => radlib_fillin.radlib_fillin_id,
          :radlib_url => Yetting.domain + "r/#{radlib_id}",
          :error_name => nil,
          :error_code => nil,
          :reason => nil,
          :help_text => nil,
          :backtrace => nil
      }
    end

  rescue Exception => e
    raise e unless RADLIB_FILLIN_ERRORS.has_key?(e.message.to_sym)
    result = {
        :success => false,
        :radlib_id => radlib_id,
        :radlib_fillin_id => nil,
        :radlib_url => Yetting.domain + "r/#{radlib_id}",
        :error_name => e.message.to_s,
        :error_code => ErrorCodes::RADLIB_FILLIN_ERRORS[e.message.to_sym][0],
        :reason => ErrorCodes::RADLIB_FILLIN_ERRORS[e.message.to_sym][1],
        :help_text => ErrorCodes::RADLIB_FILLIN_ERRORS[e.message.to_sym][2],
        :backtrace => e.backtrace.inspect
    }
  end



  # Validates the like_radlib_fillin
  # if valid
  #   Adds a like to the radlib itself (if not already counted, via RadlibStory Class)
  #     Adds a likes_received to author of radlib (if not already counted)
  #     Runs Analytics on RadlibStory and Radlib Author (if new data, handled by RadlibStory Class)
  #   Adds a like to the radlib fillin (if not already counted)
  #   Adds a likes_made to user who liked (if not already counted)
  #   if like was new
  #     Runs Analytics on User who liked
  # returns result Hash
  def action_like_radlib_fillin(radlib_id, radlib_fillin_id)

    if validate_like_fillin(radlib_id, radlib_fillin_id)

      # do this for the radlib itself to track total likes, this will also increase it for the radlib author
      radlib = find_radlib_by_radlib_id(radlib_id)

      # add a like to the radlib itself (it checks if it's already been counted),
      # also handles adding likes_received for the radlib author, and Analytics for Radlib and Author
      radlib.add_like(@uid)

      radlib_fillin = RadlibFillin.new({:retrieve => true, :radlib_fillin_id => radlib_fillin_id})

      # get current likes
      new_likes_count = radlib_fillin.num_likes

      if radlib_fillin.add_like(@uid)

        # increase by one since it was a success
        new_likes_count += 1

        # add one to the count of likes User has made
        increment_likes_made

        # Run Analytics on new data
        Analytics.analyze_user(self)
      end

      result = {
          :success => true,
          :radlib_id => radlib_id,
          :radlib_fillin_id => radlib_fillin_id,
          :radlib_url => Yetting.domain + "r/#{radlib_id}",
          :likes_count => new_likes_count,
          :total_radlib_likes => radlib.num_likes,
          :error_name => nil,
          :error_code => nil,
          :reason => nil,
          :help_text => nil,
          :backtrace => nil
      }
    end

  rescue Exception => e
    raise e unless RADLIB_LIKE_FILLIN_ERRORS.has_key?(e.message.to_sym)
    result = {
        :success => false,
        :radlib_id => radlib_id,
        :radlib_fillin_id => radlib_fillin_id,
        :radlib_url => Yetting.domain + "r/#{radlib_id}",
        :error_name => e.message.to_s,
        :error_code => ErrorCodes::RADLIB_LIKE_FILLIN_ERRORS[e.message.to_sym][0],
        :reason => ErrorCodes::RADLIB_LIKE_FILLIN_ERRORS[e.message.to_sym][1],
        :help_text => ErrorCodes::RADLIB_LIKE_FILLIN_ERRORS[e.message.to_sym][2],
        :backtrace => e.backtrace.inspect
    }
  end


  def action_comment_on_fillin(radlib_id, radlib_fillin_id, comment_text)

    if validate_like_fillin(radlib_id, radlib_fillin_id)
      radlib_fillin = RadlibFillin.new({:retrieve => true, :radlib_fillin_id => radlib_fillin_id})
      comment_index = radlib_fillin.add_comment(@uid, comment_text)

      # increment the count for comments made
      increment_comments_made

      Analytics.analyze_user(self)

      Rails.logger.debug(intense_red(comment_index))
      result = {
          :success => true,
          :radlib_id => radlib_id,
          :radlib_fillin_id => radlib_fillin_id,
          :comment_count => comment_index,
          :author_name => @firstname + " " + @lastname,
          :author_profile_img => @fb_img_square,
          :comment_text => radlib_fillin[comment_index][:text],
          :timestamp => radlib_fillin[comment_index][:timestamp],
          :error_name => nil,
          :error_code => nil,
          :reason => nil,
          :help_text => nil,
          :backtrace => nil
      }
    end
  rescue Exception => e
    raise e unless RADLIB_COMMENT_FILLIN_ERRORS.has_key?(e.message.to_sym)
    result = {
        :success => false,
        :radlib_id => radlib_id,
        :radlib_fillin_id => radlib_fillin_id,
        :radlib_url => Yetting.domain + "r/#{radlib_id}",
        :error_name => e.message.to_s,
        :error_code => ErrorCodes::RADLIB_COMMENT_FILLIN_ERRORS[e.message.to_sym][0],
        :reason => ErrorCodes::RADLIB_COMMENT_FILLIN_ERRORS[e.message.to_sym][1],
        :help_text => ErrorCodes::RADLIB_COMMENT_FILLIN_ERRORS[e.message.to_sym][2],
        :backtrace => e.backtrace.inspect
    }
  end






  #### PUBLIC METHODS
  public

  def add_radlib_to_created(radlib_id)
    doc = get_document(@docs[:radlibs_created])
    create_default_docs unless doc

    radlibs = doc[:radlibs]
    radlibs.unshift(radlib_id)
    doc[:radlibs] = radlibs

    atomic_count = increase_atomic_count(@docs[:num_radlibs_created])

    if radlibs.size != atomic_count
      replace_document(@docs[:num_radlibs_created], radlibs.size)
    end

    replace_document(@docs[:radlibs_created], doc)
  end

  def add_radlib_filled(radlib_id)
    doc = get_document(@docs[:radlibs_filled])
    create_default_docs unless doc

    radlibs = doc[:radlibs]
    radlibs.unshift(radlib_id)
    doc[:radlibs] = radlibs

    atomic_count = increase_atomic_count(@docs[:radlibs_filled_count])

    if radlibs.size != atomic_count
      replace_document(@docs[:radlibs_filled_count], radlibs.size)
    end

    replace_document(@docs[:radlibs_filled], doc)
  end


  #### CLASS METHODS

  def self.add_radlib_to_created(uid, radlib_id)
    user = find_user_by_uid(uid)
    user.add_radlib_to_created(radlib_id) if user
  end

  def self.add_radlib_to_filled(uid, radlib_id)
    user = find_user_by_uid(uid)
    user.add_radlib_filled(radlib_id)
  end

  def add_total_like
    atomic_count = get_document(@docs[:num_likes_received])
    create_default_docs unless atomic_count
    increase_atomic_count(@docs[:num_likes_received])
  end

end