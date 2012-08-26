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
###
###
###
class RadlibStory < RadlibsBase
  include DocumentStore
  include ModelValidations
  include ModelGlobal
  extend ActiveModel::Callbacks
  extend ActiveModel::Naming

  attr_accessor :radlib_id, :radlib_title, :radlib_text_array, :author_uid, :original_sentences, :radlib_short_url

  def initialize(attr = {})
    attr = Map.new(attr)
    super


    # load passed in parameter attributes
    load_parameter_attributes attr

    # Typically in Couchbase you want to create document and then modify instead of waiting for save method at the end
    # we pass in :create => true to create this user, then we can modify the user later
    # We'll make sure it's valid by checking to see if the user already exists
    if attr.has_key_and_value?(:create)
      raise "trying to create radlib -- no valid uid passed" unless @author_uid && User.find_user_by_uid(@author_uid)
      raise "trying to create radlib -- no radlib_text_array passed" unless @radlib_text_array && radlib_text_array.length > 0
      create_new
    end

    # Either we are creating or retrieving a user, if we are retrieving, we need at least one of three possible user
    # identifiers to be passed in as an attribute/parameter
    if attr.has_key_and_value?(:retrieve)
      #unless attr.has_key_and_value?(:facebook_id) || attr.has_key_and_value?(:email) || attr.has_key_and_value?(:uid)
      #raise "trying to retrieve user -- requires facebook_id, email or uid"
      #end
      load_persisted
    end

    self
  end

  def create_doc_keys(force_reset = false)
    unless @doc_keys_setup && force_reset
      @docs = {}

      @docs[:radlib] = "rad::#{@radlib_id}"

      @docs[:num_fillins] = "rad::#{@radlib_id}::fillins_count"
      @docs[:num_likes] = "rad::#{@radlib_id}::likes_count"
      @docs[:num_comments] = "rad::#{@radlib_id}::comment_count"
      @docs[:num_commenters] = "rad::#{@radlib_id}::commenters_count"

      @docs[:num_views] = "rad::#{@radlib_id}::num_views"

      @docs[:liked_by] = "rad::#{@radlib_id}::liked_by"
      @docs[:comments_by] = "rad::#{@radlib_id}::comments_by" 

      @doc_keys_setup = true
    end
  end

  def create_default_docs
    create_doc_keys unless doc_keys_setup

    default_radlib_doc = { :type => "radlib_story",
                           :radlib_id => @radlib_id,
                           :author_uid => @author_uid,
                           :radlib_text_array => @radlib_text_array,
                           :radlib_title => @radlib_title,
                           :original_sentences => @original_sentences }

    initialize_document(@docs[:radlib], default_radlib_doc)

    initialize_document(@docs[:num_fillins], 0)
    initialize_document(@docs[:num_likes], 0)
    initialize_document(@docs[:num_comments], 0)
    initialize_document(@docs[:num_commenters], 0)
    initialize_document(@docs[:num_views], 0)

    initialize_document(@docs[:liked_by], { :users => [] } )
    initialize_document(@docs[:comments_by], { :users => [] } )

  end

  # create a new user and associated documents
  def create_new
    @radlib_id = get_new_radlib_id
    @radlib_text_array.clean_for_database
    create_default_docs
  end

  def load_persisted
    create_doc_keys(true)
    load_parameter_attributes get_document(@docs[:radlib])
    create_default_docs
  end

  #### PROPERTIES & PROPERTY OVERLOADS
  public

  def radlib_text_array=(radlib_text_array)
    @radlib_text_array = RadlibTextArray.new(radlib_text_array)
  end

  def fillins
    fillin_collection = RadlibFillinCollection.new({:radlib_id => @radlib_id})
    #Rails.logger.debug(yellow(fillins.user_entries.inspect))
    #Rails.logger.debug("")
    fillin_collection.fillins
  end

  def liked_by(get_user_objects = true)
    doc = get_document(@docs[:liked_by])

    # by default, return user objects, else return array of uid's
    if get_user_objects
      users = []
      doc[:users].each do |u|
        user = find_user_by_uid(u)
        users.push(user)
      end
      users
    else
      doc[:users]
    end
  end

  def comments_by(get_user_objects = true)
    doc = get_document(@docs[:comments_by])

    # by default, return user objects, else return array of uid's
    if get_user_objects
      users = []
      doc[:users].each do |u|
        user = find_user_by_uid(u)
        users.push(user)
      end
      users
    else
      doc[:users]
    end
  end


  def num_fillins
    get_document(@docs[:num_fillins])
  end

  def num_likes
    get_document(@docs[:num_likes])
  end

  def num_comments
    get_document(@docs[:num_comments])
  end

  def num_commenters
    get_document(@docs[:num_commenters])
  end

  def num_views
    get_document(@docs[:num_views])
  end

  def increment_view_count
    increase_atomic_count(@docs[:num_views])
  end

  # def increment_num_likes
  # this is handled by RadlibStory#add_like

  # def increment_num_comments
  # this is handled by RadlibStory#add_commenter

  # def increment_num_commenters
  # this is handled by RadlibStory#add_commenter

  # def increment_num_fillins
  # this is handled by RadlibStory#add_fillin

  #### PUBLIC METHODS
  public

  # add like to this radlib from a user
  # returns boolean on whether that like was new
  def add_like(uid_of_liker)
    doc = get_document(@docs[:liked_by])

    Rails.logger.debug(doc.inspect)

    # unless this has already been liked by this person (liking_uid)
    unless doc[:users].include?(uid_of_liker)

      # add to front
      doc[:users].unshift(uid_of_liker)

      # store the array of uid's
      replace_document(@docs[:liked_by], doc)

      # increase the number of unique likes on this radlib
      increase_atomic_count(@docs[:num_likes])

      # add to likes_received for the author of this radlib
      author = find_user_by_uid(@uid)
      author.increment_num_likes_received if author

      Analytics.analyze_most_popular_radlibs(self)
      Analytics.analyze_user(author)
      true
    end

    false
  end

  # Also increases count of @docs[:num_comments]
  def add_commenter(uid_of_commenter)

    # increase the count of comments on this radlib on all fillins
    increase_atomic_count(@docs[:num_comments])

    doc = get_document(@docs[:comments_by])

    # unless this has already been liked by this person (liking_uid)
    unless doc[:users].include?(uid_of_commenter)

      # add to front
      doc[:users].unshift(uid_of_commenter)

      # store the array of uid's
      replace_document(@docs[:comments_by], doc)

      # increase the number of unique likes on this radlib
      increase_atomic_count(@docs[:num_commenters])

      # add to likes_received for the author of this radlib
      author = find_user_by_uid(@uid)
      author.increment_num_comments_received

      Analytics.analyze_most_popular_radlibs(self)
      Analytics.analyze_user(author)
      true
    end

  end

  # attr[:uid] => user's internal uid
  # AND
  # attr[:radlib_text_array] => actual radlib text array with user inputs already mixed in at appropriate indices,
  #     needs to be a RadlibTextArray object
  # returns radlib_fillin_id
  def add_fillin(attr)
    new_fillin_index = increase_atomic_count(@docs[:num_fillins])

    fillin_params = {
        :create => true,
        :radlib_id => radlib_id,
        :fillin_index => new_fillin_index,
        :uid => attr[:uid],
        :user_inputs => attr[:radlib_text_array].user_inputs
    }

    RadlibFillin.new(fillin_params)
  end


end