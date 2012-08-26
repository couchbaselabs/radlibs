require 'json'

class ApiController < ApplicationController
  layout nil
  include DocumentStore


  def lookup_fb_friend
    input_name = params["name"].downcase

    matches = []

    if input_name && input_name.length > 0


      friends = session[:fb_friends]

      friends.each do |f|
        f["name"].downcase.split.each do |i|
          if i.start_with? input_name

            matches.push([f["name"], f["id"]])
          end
        end
      end


    end

    respond_to do |format|
      format.json { render :json => matches.uniq.to_json }
    end
  end


# lookup definitions for a word
# returns json dictionary of the response from wordnik, no massaging necessary
  def lookup_word
    word = params["word"].to_s.downcase
    include_pronounce = params["include_pronounce"]

    json = Wordnik.word.get_definitions("#{word}", :use_canonical => true)

    # if we also want to include the pronounciation of that word we can do so this way
    if include_pronounce

      # lookup pronounciation as a separate call to wordnik
      pronounce = Wordnik.word.get_text_pronunciations(word)

      # merge the response into the existing json document if json isn't empty, meaning the word wasn't found
      json[0][:pronounciation] = pronounce[0]["raw"] unless json.empty?

    end

    #Rails.logger.debug json.inspect

    # send the definitions back to the caller as json
    respond_to do |format|
      format.json { render :json => json }
    end
  end


# lookup all the potential parts of speech of each word in an array of words
# returns a json hash dictionary of the potential parts of speech of each word
#
#
# note: we could do this through lookup_word, by calling it through ajax one at a time, however, that requires many
#         ajax calls to do a full sentence, this requires only one ajax call, and as more words get added to
#         Couchbase, this gets faster and faster
#
# another note: technically we cannot store Wordnik data, in this case we are not trying to duplicate information
#         we are only storing parts of speech, and got permission to do so since this is a non-commercial
#         demonstration app
#
  def lookup_parts_of_speech
    words = params["words"]

    pos_hash = {}
    pos = []
    doc_exists = false

    # first check if anything was passed in, then iterate through each word in the array passed
    if words

      words.each do |w|
        Rails.logger.debug("---------------------------------------------")
        Rails.logger.debug("word = #{w.downcase}")
                         # check to see if we have a document already for this word's parts of speech
        pos = get_document("pos::#{w.downcase}")
        doc_exists = true if pos

        if pos
          pos_size = pos.size
          pos.delete_if {|p| p.nil? }

          if pos_size < pos.size
            replace_document("pos::#{w.downcase}", pos)
          end
        end

        unless pos
          json = Wordnik.word.get_definitions("#{w.downcase}", :use_canonical => true)

          Rails.logger.debug(json.pretty_inspect)
          # Iterate through each definition and gather potential parts of speech for the word as an array
          pos = []
          json.each do |j|

            this_pos = j["partOfSpeech"]

            # if this part of speech is one of the many forms verbs can take, let's simplify it to just verb
            if this_pos != "adverb" && this_pos && this_pos.include?("verb")
              this_pos = "verb"
            end

            # if it isn't already included, add to array, unless it can be an idiom, abbreviation, or interjection, we're trying to keep it simple here
            unless pos.include?(this_pos) || this_pos == "idiom" || this_pos == "interjection" || this_pos == "abbreviation"
              pos.push(this_pos)
            end
          end

          # after iterating through, let's clean a few things up, we have some things that are rare but true...
          pos = process_parts_of_speech_exceptions(w.downcase, pos)

          # clean up any nil's that happened to sneak into array from Wordnik...
          pos.delete_if {|p| p.nil? }

          begin
            replace_document("pos::#{w.downcase}", pos)
          rescue Couchbase::Error::NotFound
            create_document("pos::#{w.downcase}", pos)
          end

        end

        Rails.logger.debug("pos = " + pos.inspect)

        # add this word to the hash, and go to the next word
        pos_hash["#{w}".to_sym] = { :word => "#{w}", :pos => pos }
        Rails.logger.debug("---------------------------------------------")
      end
    end

    Rails.logger.debug(pos_hash.pretty_inspect)

    # return the hash of parts of speech
    respond_to do |format|
      format.json { render :json => pos_hash.to_json }
    end
  end


  def process_parts_of_speech_exceptions(word, pos_array)

    # if the word is "the", technically there are extremely rare cases it can be an adverb, but we're taking that out of the list
    if word == "the"
      return ["definite-article"]
    end

    # if the word is "a" or "an", technically there are extremely rare cases it can be a noun, preposition, or verb, but we're taking those out of the list
    if word == "a" || word == "an"
      return ["indefinite-article"]
    end

    pos_array
  end
end



