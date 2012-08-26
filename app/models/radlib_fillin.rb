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
##
## RadlibStory handles the fillin_index, and passes it to RadlibFillin, see RadlibStory#add_fillin
##
#
class RadlibFillin < RadlibsBase
  include DocumentStore
  include ModelValidations
  include ModelGlobal
  include ErrorCodes
  extend ActiveModel::Callbacks
  extend ActiveModel::Naming
  
  attr_accessor :radlib_id, :radlib_fillin_id, :fillin_index, :uid, :user_inputs
  
  def initialize(attr = {})
    attr = Map.new(attr)
    super

    # load passed in parameter attributes
    load_parameter_attributes attr

    if attr.has_key_and_value?(:create)
      if attr.has_key_and_value?(:radlib_fillin_id)
        parse_radlib_fillin_id(attr[:radlib_fillin_id])
      end
      raise "trying to create radlib_fillin -- requires radlib_id and radlib must exist, and must have fillin_index > 0" unless @radlib_id && RadlibFillin.find_radlib_by_radlib_id(@radlib_id) && @fillin_index && @fillin_index > 0
      raise "trying to create radlib_fillin -- requires uid and user must exist" unless @uid && RadlibFillin.find_user_by_uid(@uid)
      raise "trying to create radlib_fillin -- requires user_inputs" unless @user_inputs
      create_new
    end

    # Either we have at least radlib_id and fillin_index, or we have radlib_fillin_id
    if attr.has_key_and_value?(:retrieve)
      if attr.has_key_and_value?(:radlib_fillin_id)
        parse_radlib_fillin_id(attr[:radlib_fillin_id])
      end
      unless attr.has_key_and_value?(:radlib_fillin_id) || (attr.has_key_and_value?(:radlib_id) && attr.has_key_and_value?(:fillin_index))
        raise "trying to retrieve radlib_fillin -- requires radlib_fillin_id or (radlib_id and fillin_index)"
      end
      load_persisted
    end
    self
  end
  
  

  #### PRIVATE/DEFAULT/OVERLOADED METHODS

  private

  def create_doc_keys(force_reset = false)
    unless @doc_keys_setup || force_reset
      @docs = {}
      
      @docs[:fillin] = "radfill::#{radlib_id}::#{@fillin_index}"
                     
      @docs[:num_views] = "radfill::#{@radlib_id}::#{@fillin_index}::views"
      @docs[:num_comments] = "radfill::#{@radlib_id}::#{@fillin_index}::comment_count"
      @docs[:num_likes] = "radfill::#{@radlib_id}::#{@fillin_index}::likes"      

      @docs[:liked_by] = "radfill::#{@radlib_id}::#{@fillin_index}::liked_by"

      @doc_keys_setup = true
    end
  end

  def create_default_docs
    create_doc_keys unless doc_keys_setup

    default_doc = { 
      :type => "radlib_fillin",
      :radlib_fillin_id => @radlib_fillin_id,
      :radlib_id => @radlib_id,
      :fillin_index => @fillin_index,
      :uid => @uid,
      :user_inputs => @user_inputs
      }
    
    initialize_document(@docs[:fillin], default_doc)
    
    initialize_document(@docs[:num_views],0)
    initialize_document(@docs[:num_comments],0)
    initialize_document(@docs[:num_likes],0)

    initialize_document(@docs[:liked_by],{ :users => [] })
  end


  def parse_radlib_fillin_id(radlib_fillin_id)
    @radlib_fillin_id = radlib_fillin_id

    # note: make sure to be consistent with @docs[:fillin] for the matches
    @radlib_id = radlib_fillin_id.gsub("radfill::", "").match(/[\d]+[^:]/)
    @fillin_index = radlib_fillin_id.gsub("radfill::", "").match(/(::)([\d]+)/)[2]

  end

  # create a new user and associated documents
  def create_new
    create_doc_keys(true)
    @radlib_fillin_id = @docs[:fillin] unless @radlib_fillin_id && @radlib_fillin_id.length > 0 # if only the radlib_id and fillin_index were passed, set the @radlib_fillin_id
    create_default_docs
  end

  def load_persisted
    create_doc_keys(true)
    load_parameter_attributes get_document(@docs[:fillin])
    create_default_docs # in case we have added some docs to this class
  end


  #### PROPERTIES & PROPERTY OVERLOADS
  public
  
  def num_views
    get_document(@docs[:num_views])
  end
  
  def num_comments
    get_document(@docs[:num_comments])
  end

  def num_likes
    get_document(@docs[:num_likes])
  end

  def increment_num_views
    increase_atomic_count(@docs[:num_views])
  end

  # def increment_num_likes
  # replaced by RadlibFillin#add_like

  def increment_num_comments

  end

  # returns boolean on whether the "like" was new
  def add_like(uid)
    # get the list of users who have liked this fillin
    doc = get_document(@docs[:liked_by])
    
    # unless this has already been liked by this person (liking_uid)
    unless doc[:users].include?(uid)
      # add to list
      doc[:users].unshift(uid)
      
      # store the new list
      replace_document(@docs[:liked_by], doc)

      # increase the count of likes for the fillin
      increase_atomic_count(@docs[:num_likes])

      return true
    end

    false
  end

  # returns index of new comment
  def add_comment(uid, comment_text)

    radlib = find_radlib_by_radlib_id(radlib_id)

    author = find_user_by_uid(radlib.author_uid)
    author.increment_comments_received

    comment_index = increase_atomic_count(@docs[:num_comments])
    timestamp = Time.now.getutc
    comment_key = radlib_fillin_id + "::comment::" + comment_index.to_s

    comment_doc = {
        :type => "radlib_fillin_comment",
        :author => uid,
        :text => comment_text,
        :timestamp => timestamp
    }

    create_document(comment_key, comment_doc)
    comment_index
  end

  # shortcut to access comments by index, also retrieves User Object
  def [](comment_index)
    if @radlib_fillin_id && comment_index.to_i > 0 && comment_index.to_i <= num_comments.to_i
      key = "#{@radlib_fillin_id}::comment::#{comment_index.to_s}"
      doc = get_document(key)
      Rails.logger.debug(doc.inspect)
      doc[:user] = find_user_by_uid(doc[:author])
      doc
    else
      nil
    end
  end

end