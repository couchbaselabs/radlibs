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
class RadlibTextArray < Array

  attr_reader :num_words, :num_sentences, :num_blanks, :num_blanks_by_type

  def initialize(radlib_text_array)
    reset_counts
    super
    radlib_text_array.each_with_index do |v,i|
      self[i] = v
    end
  end

  def reset_counts
    @num_words = @num_sentences = @num_blanks = 0
    @num_blanks_by_type = {
        :adjective => 0,
        :adverb => 0,
        :noun => 0,
        :proper_noun => 0,
        :verb => 0
    }
    self
  end

  # because dup method on arrays is shallow (doesn't dup nested hash/array), dup each element underneath
  def dup

    # duplicate self
    rta = super

    # iterate through array and dup each hash
    rta.each_with_index do |w_hash, index|

      # dup the hash at this index
      rta[index] = w_hash.dup

      # to be complete, also dup the key/values in the hash, in case another hash/array is nested
      w_hash.each_pair do |k, v|
        rta[index][k] = v.dup if v.is_a? Hash
      end
    end

    # now everything should have new object_id's
    rta
  end

  # return a hash that has all the stats on the radlib_text_array
  def word_stats(force_recount = false)
    process_words unless @num_words && @num_words > 0 && force_recount
    {
        :num_words => @num_words,
        :num_sentences => @num_sentences,
        :num_blanks => @num_blanks,
        :num_blanks_by_type => @num_blanks_by_type
    }
  end


  # iterate through the entries in radlib_text_array and count the words
  def process_words
    reset_counts
    # iterate through radlib_array and add counts
    self.each do |w|
      Rails.logger.debug(w.inspect)
      case w["type"]
        when "word"
          @num_words += 1
          if w["selectable"] && w["selected"]
            @num_blanks += 1
            # fix for old radlibs
            unless w["user_pos"]
              w["user_pos"] = w["predicted_pos"]
            end
            type = w["user_pos"].gsub("-", "_").to_sym
            Rails.logger.debug(type)
            @num_blanks_by_type[type] += 1
          end
        when "whitespace"
          # don't need to do anything here
        when "punc"
          @num_sentences += 1 if w["text"] == "." || w["text"] == "!" || w["text"] == "?"
      end
    end
  end

  def user_inputs
    values = []
    self.each_with_index do |w, index|
      if w["selected"]
        values.push({ :radlib_text_array_index => index, :fillin_word => w["fillin_word"]} )
      end
    end
    values
  end

  def clean_for_database
    self.each do |w|

      # fixes "true" strings to true booleans
      w["selectable"] = (w["selectable"] == "true" || w["selectable"] == true ? true : false)
      w["selected"] = (w["selected"] == "true" || w["selected"] == true ? true : false)

      # remove "display" key/value from each word (which is HTML from frontend)
      w.delete("display")

      # if the word is a word (not whitespace or punctuation), copy predicted_pos (part of speech) to user,
      # if one isn't already set
      if w["type"] == "word"
        unless w.has_key?("user_pos")
          w["user_pos"] = w["predicted_pos"]
        end
      end # end of type=="word"

    end # end of self.each
  end

end

x = [{"index"=>0, "type"=>"word", "text"=>"Shifting", "selectable"=>true, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>1, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>2, "type"=>"word", "text"=>"a", "selectable"=>false, "selected"=>false, "predicted_pos"=>"indefinite-article", "user_pos"=>"indefinite-article"},{"index"=>3, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>4, "type"=>"word", "text"=>"car", "selectable"=>true, "selected"=>true, "predicted_pos"=>"noun", "user_pos"=>"adjective"},{"index"=>5, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>6, "type"=>"word", "text"=>"transmission", "selectable"=>true, "selected"=>true, "predicted_pos"=>"noun", "user_pos"=>"noun"},{"index"=>7, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>8, "type"=>"word", "text"=>"with", "selectable"=>true, "selected"=>false, "predicted_pos"=>"preposition", "user_pos"=>"preposition"},{"index"=>9, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>10, "type"=>"word", "text"=>"a", "selectable"=>false, "selected"=>false, "predicted_pos"=>"indefinite-article", "user_pos"=>"indefinite-article"},{"index"=>11, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>12, "type"=>"word", "text"=>"dogleg", "selectable"=>true, "selected"=>true, "predicted_pos"=>"noun", "user_pos"=>"adjective"},{"index"=>13, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>14, "type"=>"word", "text"=>"shift", "selectable"=>true, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>15, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>16, "type"=>"word", "text"=>"pattern", "selectable"=>true, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>17, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>18, "type"=>"word", "text"=>"can", "selectable"=>true, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>19, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>20, "type"=>"word", "text"=>"be", "selectable"=>true, "selected"=>false, "predicted_pos"=>"verb", "user_pos"=>"verb"},{"index"=>21, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>22, "type"=>"word", "text"=>"confusing", "selectable"=>true, "selected"=>true, "predicted_pos"=>"adjective", "user_pos"=>"adjective"},{"index"=>23, "type"=>"punc", "text"=>",", "selectable"=>false, "selected"=>false},{"index"=>24, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>25, "type"=>"word", "text"=>"if", "selectable"=>true, "selected"=>false, "predicted_pos"=>"noun", "user_pos"=>"noun"},{"index"=>26, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>27, "type"=>"word", "text"=>"you", "selectable"=>false, "selected"=>false, "predicted_pos"=>"pronoun", "user_pos"=>"pronoun"},{"index"=>28, "type"=>"punc", "text"=>"'", "selectable"=>false, "selected"=>false},{"index"=>29, "type"=>"word", "text"=>"re", "selectable"=>true, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>30, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>31, "type"=>"word", "text"=>"used", "selectable"=>true, "selected"=>false, "predicted_pos"=>"verb", "user_pos"=>"verb"},{"index"=>32, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>33, "type"=>"word", "text"=>"to", "selectable"=>true, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>34, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>35, "type"=>"word", "text"=>"something", "selectable"=>false, "selected"=>false, "predicted_pos"=>"unknown", "user_pos"=>"unknown"},{"index"=>36, "type"=>"whitespace", "text"=>" ", "selectable"=>false, "selected"=>false},{"index"=>37, "type"=>"word", "text"=>"else", "selectable"=>true, "selected"=>true, "predicted_pos"=>"adjective", "user_pos"=>"adjective"},{"index"=>38, "type"=>"punc", "text"=>".", "selectable"=>false, "selected"=>false}]