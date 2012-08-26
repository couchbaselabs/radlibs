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
# To Keep error handling and messaging DRY and centralized, we created a ErrorCodes module that is included in the User Object
# This way, all error messages and numeric error codes are in one place and MUCH easier to maintain
#
# It is a conscious deviation from using ActiveModel which puts all error messages in each class
#   and it's difficult to maintain unique numeric error codes across classes
#
# Developer Note: **It is the intention to make this integrate more with ActiveModel in the future, but for now this works just fine
#
# module ErrorCode
#   has one GLOBAL_ERRORS constant
#   the rest correlate directly with User Actions, one Hash for each User Action
#   See app/models/user.rb #### USER ACTIONS section for the User Actions Code
#   See app/models/model_validations.rb for each validation of User Actions that raise exceptions with these ErrorCode symbols

module ErrorCodes

  # Format of Errors
  # [0] = Error Code
  # [1] = Error Message
  # [2] = Friendly Help Text, Tips, etc.

  GLOBAL_ERRORS = {
      :not_authenticated => [-1, "You must Log In in to create, like, fill-in, or comment on a Radlib.",
                             "You didn't authorize this app on Facebook, haven't Logged In yet for this session, or Log In didn't work, please try again."]
  }

  RADLIB_CREATE_ERRORS = {
      :no_title => [10, "You need to have a title!",
                    "Titles can be misleading and zany, that's part of the fun., Maybe try to use the words that aren't your blanks as part of it."],

      :no_text => [11, "You have to have some text for the Radlib!",
                   "Radlibs have to have a story, try going back and typing in a sentence (or two)"],

      :no_words_selected => [12, "You have to select words for blanks for others to fill-in!",
                             "You have to select words to turn into blanks first before saving! Click on <i>teal words</i> in your sentence(s) and also confirm their parts of speech... then click Save again!"],

      :unknown_pos => [13, "Every blank has to have a known part of speech (pos)!",
                        "Every blank has to have a correct part of speech (pos) associated with it to give users a clue as to what type of word to put in, select an appropriate part of speech from green table below Radlib text for each word-blank."]
  }

  RADLIB_FILLIN_ERRORS = {
      :radlib_not_found => [20, "We couldn't find the radlib you filled in!",
                            "If this happens, there's a bug in the system, or some data was deleted."],

      :no_text => [21, "You have to have radlib text to fill words in!",
                   "If this happens, there's a bug in the system, the ajax failed to send data, there was a parsing problem with the submitted array, or subterfuge!"],

      :not_all_blanks_filled => [22, "You still have some blanks to fill out!",
                                 "Every blank has to be filled with your word choice, preferably with the correct part of speech for that blank!"],

      :wrong_type => [23, "System Error, we have to fix something",
                                 "This shouldn't happen, but radlib_text_array was not a RadlibTextArray Object"]
  }

  RADLIB_LIKE_FILLIN_ERRORS = {
      :radlib_not_found => [30, "We couldn't find the radlib you tried to Like!",
                            "If this happens, there's a bug in the system, or some data was deleted."],

      :radlib_fillin_not_found => [31, "We couldn't find the radlib fillin you tried to Like!",
                                    "If this happens, there's a bug in the system, or some data was deleted."],

      :already_liked => [32, "You already liked this, thanks for the enthusiasm!",
                           "If this happens, there's a bug in the system because the Like button should be disabled!"]
  }

  RADLIB_COMMENT_FILLIN_ERRORS = {
      :radlib_not_found => [40, "We couldn't find the radlib you tried to Like!",
                            "If this happens, there's a bug in the system, or some data was deleted."],

      :radlib_fillin_not_found => [41, "We couldn't find the radlib fillin you tried to Like!",
                                   "If this happens, there's a bug in the system, or some data was deleted."],

      :no_text => [42, "You have to type some text into your comment!",
                         "I don't need to explain this do I?"]
  }

end