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
## Site-wide Analytics
##
# Since this class is used site-wide, and tracks across sessions,
#   we are making the variables class constants, and all methods are class methods,
#   initialize should be called *once* on app init or after deleting all documents (db bucket flush)
#   to setup default documents and keys
#
# This *could* be a module instead of a class, but it could also be confusing to
#   add these methods to another class, so instead we'll make it a class so methods are called explicitly:
#   i.e. instead of User.check_most_prolific (self), we use Analytics.check_most_prolific (user)
#   This reduces confusion for readers, although functionally it doesn't change
#
#
# In Couchbase 2.0 you can use Views to determine some of this, but we are using Couchbase 1.8
# and therefore we are analyzing these lists of most or top users incrementally by tracking
# after user actions.
#
# A number of different strategies are employed to reduce roundtrips to the database to the minimum
# while still tracking these statistics.
#
class Analytics

  USER_COUNT_START    = Yetting.user_count_start
  RADLIB_COUNT_START  = Yetting.radlib_count_start

  # note: for the :most_x keys, we generate an additional key, appending ::min for minimum value to get on list
  # see create_default_docs() to see the pattern
  DOCS = {
      :user_count => "u::count",
      :radlib_count => "rad::count",

      :superusers => "superusers",
      :superusers_count => "superusers::count",

      :site_views_count => "site::views",  # total site views, for all pages
      :site_likes_count => "site::likes", # total site likes made for all fillins for all users
      :site_comments_count => "site::comments", # total site comments made for all fillins for all users
      :site_facebook_friends => "site::facebook_friends", # total count of all facebook friends, it's not *really* accurate since it doesn't check for unique between each user

      :latest_activity_stub => "latest::activity::",
      :latest_activity_count => "latest::activity::count",  # non-partial list of activity taken on the site by user, keeps incrementing

      :latest_users_signedup => "latest::users_signedup",
      :latest_users_loggedin => "latest::users_loggedin",

      :most_prolific => "most::prolific",      # users who create, comment, and fillin the most (cross product)
      :most_radlibs => "most::radlibs",        # users who have generated the most primary content
      :most_fillins => "most::fillins",        # users who generated the most secondary content (by filling in radlibs)
      :most_fillins_by_others => "most::fillins_by_others", # users who generated the most secondary content (by having their radlibs filled in)
      :most_comments_made => "most::comments_made", # users who have generated the most tertiary content
      :most_prolific_likers => "most::prolific_likers", # users who have liked the most (a count of how many likes a user has made (i.e. how many times user clicked like))
      :most_active_users => "most::active_users",  # users who visit the most, perhaps the most time spent on site too?

      :most_popular_users => "most::popular::users",
      :most_popular_radlibs => "most::popular::radlibs"
  }.freeze

  # this array is used for track_daily_stats()
  # if the key is in this array, it will be *NOT* tracked daily
  # it uses the DOCS and deletes any keys that are in this array and sets a new constant
  DOCS_DAILY_REMOVE = [
      :latest_activity_stub,
      :latest_users_signedup,
      :latest_users_loggedin
  ].freeze

  # This is set for all lists to track Top n, (i.e. Top 10, or Top 25), it is set in the yettings application settings file
  MOST_LIST_SIZE = Yetting.analytics_most_list_size

  def initialize(attr = {})
    self.class.create_default_docs
  end

  # Make all these methods class methods
  class << self
    include Term::ANSIColor
    include DocumentStore
    include ModelGlobal

    def create_default_docs
      DocumentStore.initialize_document(DOCS[:user_count], USER_COUNT_START)
      DocumentStore.initialize_document(DOCS[:radlib_count], RADLIB_COUNT_START)

      DocumentStore.initialize_document(DOCS[:site_views_count], 0)
      DocumentStore.initialize_document(DOCS[:site_likes_count], 0)
      DocumentStore.initialize_document(DOCS[:site_comments_count], 0)
      DocumentStore.initialize_document(DOCS[:site_facebook_friends], 0)
      DocumentStore.initialize_document(DOCS[:latest_activity_count], 0)


      DocumentStore.initialize_document(DOCS[:latest_users_signedup], { :users => [] })
      DocumentStore.initialize_document(DOCS[:latest_users_loggedin], { :users => [] })

      DocumentStore.initialize_document(DOCS[:most_prolific], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_prolific] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_radlibs], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_radlibs] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_fillins], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_fillins] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_fillins_by_others], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_fillins_by_others] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_comments_made], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_comments_made] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_prolific_likers], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_prolific_likers] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_active_users], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_active_users] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_popular_radlibs], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_popular_radlibs] + "::min", 0)

      DocumentStore.initialize_document(DOCS[:most_popular_users], { :list => [] })
      DocumentStore.initialize_document(DOCS[:most_popular_users] + "::min", 0)

    end



    ## ********************************************************************************
    ## Analytics DAILY STATS method
    ## This takes all keys and tracks them by day by coping values from beginning of day
    ## to the end of day, and creates indicator keys to know that this has been done.
    ##
    ## The only thing that is required to make this work is to hit the site from any browser
    ## on any page, once per day by anyone.
    ## ********************************************************************************

    def track_daily_stats
      # if there is no constant defined,
      unless defined?(DOCS_DAILY)
        keys = DOCS.dup
        keys.delete_if {|k,v| DOCS_DAILY_REMOVE.include?(k)}
        self.class.const_set("DOCS_DAILY", keys)
      end


                                          # create the daily stat indicator key
      today = Time.now.strftime("%Y%m%d") #20120614
      todays_stats_key = "stats::#{today}"

      # check if stats have been run today
      todays_stats_exist = DocumentStore.document_exists?(todays_stats_key)

      # if not, run the stats for today
      unless todays_stats_exist

        # set today's stat key immediately, this just indicates that the stats have been run today
        # this will fail if the key gets added between check above and now (nanoseconds),
        # will rescue below and do nothing
        DocumentStore.create_document(todays_stats_key, 1, {:quiet => false})

        # iterate through and retrieve values for each key, and store them as a daily value
        DOCS_DAILY.each do |k,doc_key|
          # get value of document
          doc_val = DocumentStore.get_document(doc_key)

          # create key for today's stats for that key
          daily_key = doc_key + "::#{today}"

          # store value with daily stat key
          DocumentStore.create_document(daily_key, doc_val)
        end
      end


    rescue Couchbase::Error::KeyExists
      # do nothing if todays_stats_key exists when trying to create

    end


    ## ********************************************************************************
    ## Analytics GROUP Methods
    ## (this takes a user and does all the analytics based on changes in user stats)
    ## ********************************************************************************

    # shortcut method to analyze all the user stat changes across all analytics
    # typically we would restrict the analytics analysis after a particular action
    def analyze_user(user)
      analyze_most_prolific(user)
      analyze_most_active_users(user)
      analyze_most_comments_made(user)
      analyze_most_prolific_likers(user)
      analyze_most_radlib_fillins_by_others(user)
      analyze_most_radlib_fillins_by_user(user)
      analyze_most_radlibs_created(user)
      self
    end

    private

    # this method is a private shortcut method for retrieving to keep things DRY for doc[:most_x] lists
    # ordered array of [uid, score_value]
    #
    # :list = [ [uid, score_value], [uid, score_value], ... ]
    # i.e. list = [ [10001, 500], [10002, 480], ...]
    def get_most_generic_for_users(doc_key, top = 5)
      doc = DocumentStore.get_document(doc_key)

      list = doc[:list]

      # now take all the uid's from activities and create an array of uid's
      keys = []
      list.each do |item|
        keys.push(item[0])
      end

      # if size > top (item count), trim back the array to the number of items desired
      keys = keys.first(top) if keys.size > top

      Rails.logger.debug("Most: #{doc_key}")
      Rails.logger.debug(keys.inspect)
      Rails.logger.debug(" ")

      # retrieve Users
      x = get_multiple_users_by_uid(keys)
      #Rails.logger.debug(x.inspect)
      x
    end

    # same as get_most_generic_for_users but retrieves radlib objects by radlib_id
    def get_most_generic_for_radlibs(doc_key, top = 5)
      doc = DocumentStore.get_document(doc_key)

      list = doc[:list]

      # now take all the uid's from activities and create an array of uid's
      keys = []
      list.each do |item|
        keys.push(item[0])
      end

      # if size > top (item count), trim back the array to the number of items desired
      keys = keys.first(top) if keys.size > top

      Rails.logger.debug("Most: #{doc_key}")
      Rails.logger.debug(keys.inspect)
      Rails.logger.debug(" ")

      get_multiple_radlibs_by_radlib_id(keys)
    end



    # private shortcut method to see if new value is greater than minimum in list,
    # ties go to the first person to reach that score (so must be greater than)
    # if it's a float, we are comparing integer values, so multiply by 10000 to preserve enough significant digits
    #
    # remember, this just checks to see if it's got high enough score to analyze the list,
    #     actual values are still analyzed if it meets the minimum and all significant digits are significant
    def analyze_most_greater_than_min?(score_value, doc_key)

      # if we haven't reached the list size yet, go ahead and return true, otherwise analyze minimum score
      list_size = DocumentStore.get_document(doc_key)
      return true if list_size[:list].size < MOST_LIST_SIZE

      minimum = DocumentStore.get_document(doc_key + "::min")

      if score_value.is_a? Float
        (score_value * 10000).to_i > minimum
      else
        score_value > minimum
      end
    end



    # private shortcut method to keep things DRY for doc[:most_x] lists
    def analyze_most_generic(item_key, score_value, doc_key)
      # unless the value is bigger than the minimum to make the list, return
      return unless analyze_most_greater_than_min?(score_value, doc_key)

      doc = DocumentStore.get_document(doc_key)

      list = doc[:list]

      in_list = false

      # go through list and see if user is already in the list, if so, update the score
      list.each do |u|
        if u[0] == item_key
          u[1] = score_value
          in_list = true
          break
        end
      end

      # if user wasn't in the list, add them to the end
      unless in_list
        list.push([item_key, score_value])
      end

      # now sort the list by comparing prolific score
      list.sort! { |x,y| y[1] <=> x[1]}

      # if we added to the list, trim it back to size
      if list.size > MOST_LIST_SIZE
        list.slice!(0, MOST_LIST_SIZE)
      end

      # save minimum value to be in list (speeds value-checks up), for floats, multiple by 10000 to preserve enough significant digits, and convert to integer
      if list.last[1].is_a? Float
        DocumentStore.force_set_document(doc_key + "::min", (list.last[1] * 10000).to_i)
      else
        DocumentStore.force_set_document(doc_key + "::min", list.last[1].to_i)
      end

      # copy modified list back to doc
      doc[:list] = list

      # replace list in Couchbase
      DocumentStore.replace_document(doc_key, doc)
    end

    public

    ## ********************************************************************************
    ## Num Users
    ## ********************************************************************************

    def num_users
      # retrieve the current user count
      count = DocumentStore.get_document(DOCS[:user_count])

      # return difference between current count and start
      count - USER_COUNT_START
    end

    def increment_num_users
      DocumentStore.increase_atomic_count(DOCS[:user_count])
    end



    ## ********************************************************************************
    ## Num Radlibs
    ## ********************************************************************************

    def num_radlibs
      # retrieve the current user count
      count = DocumentStore.get_document(DOCS[:radlib_count])

      # return difference between current count and start
      count - RADLIB_COUNT_START
    end

    def increment_num_radlibs
      DocumentStore.increase_atomic_count(DOCS[:radlib_count])
    end



    ## ********************************************************************************
    ## Site Views
    ## ********************************************************************************

    def num_site_views
      DocumentStore.get_document(DOCS[:site_views_count])
    end

    def increment_site_views
      DocumentStore.increase_atomic_count(DOCS[:site_views_count])
    # the only time you would need to rescue, is if it didn't initialize
    rescue
      Analytics.new
      DocumentStore.increase_atomic_count(DOCS[:site_views_count])
    end




    ## ********************************************************************************
    ## Site Likes
    ## ********************************************************************************

    def num_site_likes
      DocumentStore.get_document(DOCS[:site_likes_count])
    end

    def increment_site_likes
      DocumentStore.increase_atomic_count(DOCS[:site_likes_count])
    end





    ## ********************************************************************************
    ## Site Comments
    ## ********************************************************************************

    def num_site_comments
      DocumentStore.get_document(DOCS[:site_comments_count])
    end

    def increment_site_comments
      DocumentStore.increase_atomic_count(DOCS[:site_comments_count])
    end



    ## ********************************************************************************
    ## Site Facebook Friends
    ## ********************************************************************************

    def num_facebook_friends
      DocumentStore.get_document(DOCS[:site_facebook_friends])
    end

    def increment_facebook_friends(amount = 1)
      DocumentStore.increase_atomic_count(DOCS[:site_facebook_friends], {:amount => amount})
    end

    def decrement_facebook_friends(amount = 1)
      DocumentStore.decrease_atomic_count(DOCS[:site_facebook_friends], {:amount => amount})
    end





    ## ********************************************************************************
    ## Activity
    ## ********************************************************************************

    def activity_count
      DocumentStore.get_document(DOCS[:latest_activity_count])
    end

    def get_latest_activity(items = 10)
      return nil unless activity_count > 0
      get_latest_activity_exact(activity_count, items)
    end

    def get_latest_activity_exact(start_index, items = 10)
      end_index = start_index - items + 1
      end_index = 1 if end_index < 1

      keys = []
      start_index.downto(end_index) do |i|
        keys.push(DOCS[:latest_activity_stub] + i.to_s)
      end

      Rails.logger.debug(intense_red("activity: #{start_index}..#{end_index}"))

      # retrieve the all activity documents in one call
      activity_docs = DocumentStore.get_documents(keys)

      Rails.logger.debug(intense_red(activity_docs.inspect))
      # now take all the uid's from activities and create an array of uid's
      keys = []
      activity_docs.each do |activity|
        keys.push(activity[:uid])
      end

      # load the users into an array
      users = get_multiple_users_by_uid(keys)

      # finally, combine the users into the activity docs and the item_indexes based on page
      # i'm using the index with activity_docs to avoid confusion,
      # I could also use "activity" in the do loop: activity[:user] = users[i]
      activity_docs.each_with_index do |activity, i|
        activity_docs[i][:item_index] = i
        activity_docs[i][:user] = users[i]
      end

      activity_docs
    end

    # reference_index is used to avoid page offset/changes between iterations of paging, meaning as new items are added to the collection,
    # they don't affect paging, so if users click "next page",
    # it won't re-order the list based on new items that have been added while they were reading
    #
    # Examples:
    #   (latest_activity_count = 127) ::: reference_index = 100, page = 1, page_size = 10
    #         => start_index = 100, end_index = 91
    #   (latest_activity_count = 133) ::: reference_index = 100, page = 2, page_size = 10
    #         => start_index = 90, end_index = 81
    #   (latest_activity_count = 145) ::: reference_index = 100, page = 3, page_size = 10
    #         => start_index = 70, end_index = 71

    def get_latest_activity_paged(reference_index, page = 1, page_size = 10)
      return nil unless activity_count > 0
      start_index = reference_index - (page * page_size)
      start_index += page_size if start_index <= 0
      end_index = start_index - (page * page_size) + 1
      end_index = 1 if end_index < 1

      # generate list of keys for the activity range (i.e. latest 10)
      keys = []
      start_index.downto(end_index) do |i|
        keys.push(DOCS[:latest_activity_stub] + i.to_s)
      end

      Rails.logger.debug(intense_red("activity: #{start_index}..#{end_index}"))

      # retrieve the all activity documents in one call
      activity_docs = DocumentStore.get_documents(keys)

      Rails.logger.debug(intense_red(activity_docs.inspect))
      # now take all the uid's from activities and create an array of uid's
      keys = []
      activity_docs.each do |activity|
        keys.push(activity[:uid])
      end

      # load the users into an array
      users = get_multiple_users_by_uid(keys)

      # finally, combine the users into the activity docs and the item_indexes based on page
      # i'm using the index with activity_docs to avoid confusion,
      # I could also use "activity" in the do loop: activity[:user] = users[i]
      activity_docs.each_with_index do |activity, i|
        activity_docs[i][:item_index] = (page * i) + i # page_size == 10 : page = 1 => 1, 2, 3,... page = 2 => 10, 11, 12
        activity_docs[i][:user] = users[i]
      end

      activity_docs
    end

    # attr[:uid] => user who did the activity
    # attr[:activity] => the activity/action they took
    #   "created_radlib", "filled_in_radlib", "liked_fillin", "commented_on_fillin"
    # attr[:radlib_id] => the radlib they took action on (or created)
    # attr[:radlib_fillin_id] => if it was a comment or a like, the radlib_fillin_id is required as well
    def add_new_activity(attr={})
      return nil if attr.empty?

      activity_index = DocumentStore.increase_atomic_count(DOCS[:latest_activity_count])
      activity = {
          :uid => attr[:uid],
          :activity => attr[:activity],
          :radlib_id => attr[:radlib_id]
      }

      if attr.has_key? :radlib_fillin_id
        activity[:radlib_fillin_id] = attr[:radlib_fillin_id]
      end

      DocumentStore.create_document(DOCS[:latest_activity_stub] + activity_index.to_s, activity)
      self
    end





    ## ********************************************************************************
    ## Latest Users Signed Up
    ## ********************************************************************************

    def get_latest_users_signed_up(top = 5)
      doc = DocumentStore.get_document(DOCS[:latest_users_signedup])
      return nil if doc[:users].empty?
      users = doc[:users]

      get_multiple_users_by_uid(users.first(top))
    end

    def add_user_signed_up(uid)
      # get array of uid's
      doc = DocumentStore.get_document(DOCS[:latest_users_signedup])

      # add uid to front of array
      doc[:users].unshift(uid)

      # replace document
      DocumentStore.replace_document(DOCS[:latest_users_signedup], doc)
      self
    end





    ## ********************************************************************************
    ## Latest Users Logged In
    ## ********************************************************************************

    def get_latest_users_logged_in(top = 5)
      doc = DocumentStore.get_document(DOCS[:latest_users_loggedin])
      return nil if doc[:users].empty?

      Rails.logger.debug("Latest Users Logged In")
      Rails.logger.debug(doc[:users].inspect)
      Rails.logger.debug("Slice List!")
      users = doc[:users]

      Rails.logger.debug(users.first(top).inspect)
      Rails.logger.debug(" ")

      get_multiple_users_by_uid(users.first(top))
    end

    def add_user_logged_in(uid)
      # get array of uid's
      doc = DocumentStore.get_document(DOCS[:latest_users_loggedin])

      # add uid to front of array
      doc[:users].unshift(uid)

      # replace document
      DocumentStore.replace_document(DOCS[:latest_users_loggedin], doc)
      self
    end






    ## ********************************************************************************
    ## Most Prolific
    ## ********************************************************************************

    # returns User objects in an array, most prolific first
    def get_most_prolific_users(num_users = 5)
      get_most_generic_for_users(DOCS[:most_prolific], num_users)
    end

    # analyze most prolific users -- users who create, comment, and fillin the most (cross product)
    # ordered array of [uid, prolific_score]
    #:list = [ [uid, prolific_score], [uid, prolific_score], ... ]
    # i.e. list = [ [10001, 500], [10002, 480], ...]
    def analyze_most_prolific(user)

      # calculate score
      prolific_score = 1
      prolific_score *= (val = user.num_radlibs_created) > 0 ? val : 1  # loads value from db *once*, then compares, and uses 1 instead of 0
      prolific_score *= (val = user.num_radlibs_filled_by_me) > 0 ? val : 1
      prolific_score *= (val = user.num_comments_made) > 0 ? val : 1

      # scale it down to avoid too big a number, using 10000.1 (with decimal ensures that we extend the value's significant digits)
      prolific_score /= 100.1

      analyze_most_generic(user.uid, prolific_score.to_f, DOCS[:most_prolific])
      self
    end





    ## ********************************************************************************
    ## Most Radlibs Created
    ## ********************************************************************************

    # returns array of User objects, users who have created the most radlibs first
    def get_most_radlibs_created(num_users = 5)
      get_most_generic_for_users(DOCS[:most_prolific], num_users)
    end

    # analyze user after user has created a new radlib
    def analyze_most_radlibs_created(user)
      analyze_most_generic(user.uid, user.num_radlibs_created.to_i, DOCS[:most_radlibs])
      self
    end



    ## ********************************************************************************
    ## Most Radlibs Filled In By a User
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_radlib_fillins_by_user(num_users = 5)
      get_most_generic_for_users(DOCS[:most_prolific], num_users)
    end

    # analyze user after filling in a radlib
    def analyze_most_radlib_fillins_by_user(user)
      analyze_most_generic(user.uid, user.num_radlibs_created.to_i, DOCS[:most_fillins])
      self
    end


    ## ********************************************************************************
    ## Most Radlibs FillIns By Others
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_radlib_fillins_by_others(num_users = 5)
      get_most_generic_for_users(DOCS[:most_prolific], num_users)
    end

    # analyze user after filling in a radlib
    def analyze_most_radlib_fillins_by_others(user)
      analyze_most_generic(user.uid, user.num_radlibs_filled_by_others.to_i, DOCS[:most_fillins])
      self
    end

    ## ********************************************************************************
    ## Most Comments Made
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_comments_made(num_users = 5)
      get_most_generic_for_users(DOCS[:most_comments_made], num_users)
    end

    # analyze user after filling in a radlib
    def analyze_most_comments_made(user)
      user = User.new
      analyze_most_generic(user.uid, user.num_comments_made.to_i, DOCS[:most_comments_made])
    end

    ## ********************************************************************************
    ## Most Radlib Fillins Liked
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_prolific_likers(num_users = 5)
      get_most_generic_for_users(DOCS[:most_prolific_likers], num_users)
    end

    # analyze user after filling in a radlib
    def analyze_most_prolific_likers(user)
      user = User.new
      analyze_most_generic(user.uid, user.num_likes_made.to_i, DOCS[:most_prolific_likers])
      self
    end

    ## ********************************************************************************
    ## Most Active Users
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_active_users(num_users = 5)
      get_most_generic_for_users(DOCS[:most_active_users], num_users)
    end

    # users who visit the most radlibs * the most visits, perhaps the most time spent on site too?
    def analyze_most_active_users(user)

      # calculate score
      most_active = 1
      most_active *= (val = user.num_site_visits) > 0 ? val : 1
      most_active *= (val = user.num_comments_made) > 0 ? val : 1
      most_active *= (val = user.num_likes_made) > 0 ? val : 1
      most_active *= (val = user.num_radlibs_filled_by_me) > 0 ? val : 1
      most_active *= (val = user.num_radlibs_created) > 0 ? val : 1

      # scale it down to avoid too big a number, using 10000.1 (with decimal ensures that we extend the value's significant digits)
      most_active /= 100.1

      # analyze result
      analyze_most_generic(user.uid, most_active.to_f, DOCS[:most_active_users])
      self
    end




    ## ********************************************************************************
    ## Most Popular Users
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_popular_users(num_users = 5)
      get_most_generic_for_users(DOCS[:most_popular_users], num_users)
    end

    # users who visit the most radlibs * the most visits, perhaps the most time spent on site too?
    def analyze_most_popular_users(user)

      # calculate score
      most_popular = 1
      most_popular *= (val = user.num_radlib_views_received) > 0 ? val : 1
      most_popular *= (val = user.num_likes_received) > 0 ? val : 1
      most_popular *= (val = user.num_radlibs_filled_by_others) > 0 ? val : 1

      # scale it down to avoid too big a number, using 10000.1 (with decimal ensures that we extend the value's significant digits)
      most_popular /= 100.1

      # analyze result
      analyze_most_generic(user.uid, most_popular.to_f, DOCS[:most_popular_users])
      self
    end

    ## ********************************************************************************
    ## Most Popular Users
    ## ********************************************************************************

    # returns User objects in an array, users with most radlibs filled in first
    def get_most_popular_radlibs(num_radlibs = 5)
      get_most_generic_for_radlibs(DOCS[:most_popular_radlibs], num_radlibs)
    end

    # users who visit the most radlibs * the most visits, perhaps the most time spent on site too?
    def analyze_most_popular_radlibs(radlib)
      # calculate score
      most_popular = 1
      most_popular *= (val = radlib.num_likes) > 0 ? val : 1
      most_popular *= (val = radlib.num_fillins) > 0 ? val : 1
      most_popular *= (val = radlib.num_views) > 0 ? val : 1

      # scale it down to avoid too big a number, using 10000.1 (with decimal ensures that we extend the value's significant digits)
      most_popular /= 100.1

      analyze_most_generic(radlib.radlib_id, most_popular.to_f, DOCS[:most_popular_radlibs])
      self
    end

    # Retrieve all associated documents setup in @docs (keys), and return as a hash (useful for debugging)
    def retrieve_all_docs
      doc_hash = {}

      DOCS.each_pair do |k,v|
        doc_hash[v] = DocumentStore.get_document(v)
      end

      doc_hash
    end

  end # class method definitions
end