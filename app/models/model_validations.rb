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
#
module ModelValidations

  # extend class methods when including this module
  def self.included(base) # :nodoc:
    base.extend ClassMethods
  end


  #### INSTANCE METHODS -- each calls ClassMethods, for DRY implementation

  def validate_create_new_radlib(radlib_title, radlib_text_array)
    self.class.validate_create_new_radlib(radlib_title, radlib_text_array)
  end

  def validate_fill_in_radlib(radlib_id, radlib_text_array)
     self.class.validate_fill_in_radlib(radlib_id, radlib_text_array)
  end

  def validate_like_fillin(radlib_id, radlib_fillin_id)
    self.class.validate_like_fillin(radlib_id, radlib_fillin_id)
  end

  def validate_comment_on_fillin(radlib_id, radlib_fillin_id, comment_text)
    self.class.validate_comment_on_fillin(radlib_id, radlib_fillin_id, comment_text)
  end


  #### CLASS METHODS

  module ClassMethods
    include ModelGlobal

    # Validate radlib text input (array of words)
    def validate_create_new_radlib(radlib_title, radlib_text_array)
      raise ArgumentError, :no_title unless radlib_title && radlib_title.length > 0
      raise ArgumentError, :no_text unless radlib_text_array

      has_blanks = false
      has_known_pos_for_blanks = true

      radlib_text_array.each do |i|
        if i["selectable"] && i["selected"]

          # at least one word is a blank
          has_blanks = true

          # radlib_text_array should have user-pos before running validation
          unless i["user_pos"]
            has_known_pos_for_blanks = false
          end

          # radlib_text_array should have a known part of speech (can't be unknown)
          unless i["user_pos"].length > 0 && i["user_pos"] != "unknown"
            has_known_pos_for_blanks = false
          end
        end
      end


      raise ArgumentError, :no_words_selected unless has_blanks
      raise ArgumentError, :unknown_pos unless has_known_pos_for_blanks

      true
    end

    def validate_fill_in_radlib(radlib_id, radlib_text_array)
      raise ArgumentError, :radlib_not_found unless find_radlib_by_radlib_id(radlib_id)
      raise ArgumentError, :no_text unless radlib_text_array
      raise ArgumentError, :wrong_type unless radlib_text_array.is_a? RadlibTextArray

      has_selected_words_filled = true
      radlib_text_array.each do |i|
        if i["selectable"] && i["selected"]
          Rails.logger.debug(i.inspect)
          if i.has_key?("fillin_word")
            if i["fillin_word"].length < 1
              has_selected_words_filled = false
            end
          else
            has_selected_words_filled = false
          end
        end
      end
      unless has_selected_words_filled
        raise ArgumentError, :not_all_blanks_filled
      end

      true
    end

    def validate_like_fillin(radlib_id, radlib_fillin_id)
      raise ArgumentError, :radlib_not_found unless find_radlib_by_radlib_id(radlib_id)
      raise ArgumentError, :radlib_fillin_not_found unless DocumentStore.get_document(radlib_fillin_id)

      liked_by_key = radlib_fillin_id + "::liked_by"
      initialize_document(liked_by_key, { :liked_by => [] } ) # make sure doc exists

      doc = get_document(liked_by_key)
      liked_by = doc[:liked_by]

      # if this has already been liked by this person
      #raise ArgumentError, :already_liked if liked_by.include?(uid)

      true
    end

    def validate_comment_on_fillin(radlib_id, radlib_fillin_id, comment_text)
      raise ArgumentError, :radlib_not_found unless find_radlib_by_radlib_id(radlib_id)
      raise ArgumentError, :radlib_fillin_not_found unless DocumentStore.get_document(radlib_fillin_id)
      raise ArgumentError, :no_text unless comment_text && comment_text.length > 0

      true
    end

  end # end ClassMethods

end # end module ModelValidations