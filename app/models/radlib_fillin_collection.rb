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
class RadlibFillinCollection < RadlibsBase
  include DocumentStore
  include ModelValidations
  include ModelGlobal
  include ErrorCodes

  attr_accessor :radlib_id, :radlib, :fillins, :num_fillins

  def initialize(attr = {})
    super

    @fillins = []

    if attr.has_key_and_value?(:radlib_id)
      @radlib = find_radlib_by_radlib_id(attr[:radlib_id])

      raise ArgumentError, "RadlibID not found" unless @radlib

      @radlib_id = @radlib.radlib_id
      @num_fillins = @radlib.num_fillins
      retrieve_fillins if @num_fillins > 0
    end
    Rails.logger.debug(intense_yellow("---------------------------------------------------------------------------------------------------------------------------------------------------------------"))

    @fillins.each_with_index do |entry, index|
      Rails.logger.debug("INDEX: [#{index}]")
      Rails.logger.debug("USER: [#{entry[:user].firstname}]")
      Rails.logger.debug("ID: [#{entry[:id]}]")
      Rails.logger.debug("ENTRY OBJ ID: #{entry[:user_inputs].object_id}")
      Rails.logger.debug("")
      entry[:user_inputs].each_with_index do |w, index|
        if (w["selected"])
          Rails.logger.debug(w.object_id)
          Rails.logger.debug(w.inspect)
          Rails.logger.debug("\t#{w["text"]} replaced by #{w["fillin_word"]}")
          Rails.logger.debug("")
        end
      end

      Rails.logger.debug(intense_yellow("---------------------------------------------------------------------------------------------------------------------------------------------------------------"))
    end

  end

  def retrieve_fillins
    # generate all the keys
    key_array = []
    @num_fillins.downto(1) do |i|
      key_array.push("radfill::#{@radlib_id}::#{i}")
    end

    # retrieve all the fillins
    fillins = get_documents(key_array)

    Rails.logger.debug(key_array)

    # if there is only one fillin, it will come back as a Hash (the one fillin), otherwise it will be an array of Hashes
    if fillins.is_a? Hash
      add_to_user_entries(fillins, 0)
    else
      fillins.each_with_index do |fillin, index|
        add_to_user_entries(fillin, index)
      end
    end

    #Rails.logger.debug(@user_entries)
  end

  def add_to_user_entries(fillin_hash, index)
    Rails.logger.debug(fillin_hash)

    # Get the User info for the user who filled in the Radlib
    fillin_user = find_user_by_uid(fillin_hash["uid"].to_i)
    radlib_fillin_id = "radfill::#{fillin_hash["radlib_id"]}::#{fillin_hash["fillin_index"]}"

    comment_count_key = radlib_fillin_id + "::comment_count"
    views_count_key = radlib_fillin_id + "::views"
    likes_count_key = radlib_fillin_id + "::likes"

    initialize_document(comment_count_key, 0)
    initialize_document(views_count_key, 0)
    initialize_document(likes_count_key, 0)

    comment_count = get_document(comment_count_key)

    # Copy the radlib text array for merging information into
    radlib_text_array_copy = @radlib.radlib_text_array.dup

    # Setup the Fillin object that's pushed into the collection
    user_entry = {
        :id => radlib_fillin_id,
        :user => fillin_user,
        :user_inputs => radlib_text_array_copy,
        :comment_count => comment_count,
        :views_count => get_document(views_count_key),
        :likes_count => get_document(likes_count_key)
    }


    # Get the User inputs array to iterate through and merge into radlib_text_array
    user_inputs_array = fillin_hash["user_inputs"]

    # for each user_input, set the radlib_text_array at that index to the user input value
    user_inputs_array.each do |input|

      # Duplicate this hash or it will have the same object_id
      user_entry[:user_inputs][input["radlib_text_array_index"]] = user_entry[:user_inputs][input["radlib_text_array_index"]].dup

      # Set the fillin_word
      user_entry[:user_inputs][input["radlib_text_array_index"]]["fillin_word"] = input["fillin_word"]

      #Rails.logger.debug(intense_blue("user_entry[:user_inputs][#{input["radlib_text_array_index"]}][\"fillin_word\"] = #{input["fillin_word"]}"))
    end

    recent_comments = []

    # get recent comments
    if comment_count > 0

      comment_key_array = []
      comment_end_index = comment_count > 5 ? comment_count - 4 : 1

      comment_count.downto(comment_end_index) do |i|
        comment_key_array.push("#{radlib_fillin_id}::comment::#{i}")
      end

      Rails.logger.debug(comment_key_array)

      # retrieve all the recent comments
      recent_comments = get_documents(comment_key_array)

      if recent_comments.is_a? Hash
        tmp = recent_comments
        recent_comments = []
        recent_comments[0] = Map.new(tmp)
      end

      Rails.logger.debug(recent_comments.inspect)
      recent_comments.each do |comment|
        Rails.logger.debug(comment.inspect)
        if comment
          Rails.logger.debug(comment[:author].to_s)
          author = find_user_by_uid(comment[:author])
          comment[:author_name] = author.firstname + " " + author.lastname
          comment[:author_profile_img] = author.fb_img_square
        end
      end

    end

    user_entry[:recent_comments] = recent_comments


    # DEBUG OUTPUT
    user_entry[:user_inputs].each_with_index do |w, index|
      if (w["selected"])
        Rails.logger.debug("[#{index}] = #{w["fillin_word"]}")
      end
    end



    @fillins[index] = user_entry
  end

end