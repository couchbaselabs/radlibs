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
module ModelGlobal
  include DocumentStore


  def get_new_radlib_id
    ModelGlobal.get_new_radlib_id
  end

  #returns the number of radlibs created so far
  def num_radlibs
    ModelGlobal.num_radlibs
  end

  def find_radlib_by_radlib_id(radlib_id, get_radlib_object = true)
    ModelGlobal.find_radlib_by_radlib_id(radlib_id, get_radlib_object)
  end

  def get_multiple_radlibs_by_radlib_id(radlib_ids, get_radlib_objects = true)
    ModelGlobal.get_multiple_radlibs_by_radlib_id(radlib_ids, get_radlib_objects)
  end

  def get_new_uid
    ModelGlobal.get_new_uid
  end


  # returns nil if the user isn't found, by default it returns a user object, set get_user_object to false if you just want the uid
  def find_user_by_facebook_id(facebook_id, get_user_object = true)
    ModelGlobal.find_user_by_facebook_id(facebook_id, get_user_object)
  end


  # returns nil if the user isn't found, by default it returns a user object, set get_user_object to false if you just want the uid
  def find_user_by_uid(uid, get_user_object = true)
    ModelGlobal.find_user_by_uid(uid, get_user_object)
  end

  def get_multiple_users_by_uid(uids, get_user_objects = true)
    ModelGlobal.get_multiple_users_by_uid(uids, get_user_objects)
  end


  # returns nil if the user isn't found, by default it returns a user object, set get_user_object to false if you just want the uid
  def find_user_by_email(email, get_user_object = true)
    ModelGlobal.find_user_by_email(email, get_user_object)
  end


  # returns the number of users signed up
  def num_users
    ModelGlobal.num_users
  end


  def add_super_user(uid)
    ModelGlobal.add_super_user(uid)
  end

  def remove_super_user(uid)
    ModelGlobal.remove_super_user(uid)
  end

  # returns the number of users signed up
  def num_superusers
    ModelGlobal.num_superusers
  end


  class << self
    include DocumentStore

    def find_radlib_by_radlib_id(radlib_id, get_radlib_object = true)
      # make sure it's a string...
      radlib_id = radlib_id.to_s

      if get_radlib_object
        radlib = nil
        radlib = RadlibStory.new ({:retrieve => true, :radlib_id => radlib_id }) if document_exists?("rad::#{radlib_id}")
        radlib
      else
        get_document("rad::#{radlib_id}")
      end
    end

    def get_multiple_radlibs_by_radlib_id(radlib_ids, get_radlib_objects = true)
      radlib_ids.each_with_index do |r, i|
        radlib_ids[i] = "rad::#{r.to_s}"
        raise ArgumentError, "get_multiple_radlibs_by_radlib_id requires that all radlib_id's in array are non-nil" if r.nil?
      end

      if get_radlib_objects
        radlib_docs = get_documents(radlib_ids)
        radlibs = []
        radlib_docs.each_with_index do |doc, i|
          radlibs[i] = RadlibStory.new ( radlib_docs[i] ) if radlib_docs[i]
        end
        radlibs
      else
        get_documents(radlib_ids)
      end
    end

    # returns nil if the user isn't found, by default it returns a user object, set get_user_object to false if you just want the uid
    def find_user_by_facebook_id(facebook_id, get_user_object = true)
      # make sure it's a string...
      facebook_id = facebook_id.to_s

      if get_user_object
        uid = get_document("fb::#{facebook_id}")
        u = nil
        u = User.new ({ :retrieve => true, :uid => uid }) if uid
        u
      else
        get_document("fb::#{facebook_id}")
      end
    end


    # returns nil if the user isn't found, by default it returns a user object, set get_user_object to false if you just want the uid
    def find_user_by_uid(uid, get_user_object = true)
      # make sure it's a string...
      uid = uid.to_s

      if get_user_object
        u = get_document("u::#{uid}")
        u = User.new ({ :retrieve => true, :uid => uid }) if u
        u
      else
        get_document("u::#{uid}")
      end
    end

    def get_multiple_users_by_uid(uids, get_user_objects = true)
      uids.each_with_index do |u, i|
        uids[i] = "u::#{u.to_s}"
        raise ArgumentError, "get_multiple_users_by_uid requires that all uid's in array are non-nil" if u.nil?
      end

      if get_user_objects
        uid_docs = get_documents(uids)
        users = []
        uid_docs.each_with_index do |doc, i|
          users[i] = User.new ( uid_docs[i] ) if uid_docs[i]
        end
        users
      else
        get_documents(uids)
      end
    end


    # returns nil if the user isn't found, by default it returns a user object, set get_user_object to false if you just want the uid
    def find_user_by_email(email, get_user_object = true)
      if get_user_object
        uid = get_document("email::#{email}")
        u = nil
        u = User.new ({ :retrieve => true, :uid => uid }) if uid
        u
      else
        get_document("email::#{facebook_id}")
      end
    end

    # returns the number of users signed up
    def num_users
      Analytics.num_users
    end

    # returns a new uid for creating/saving a new user
    def get_new_uid
      Analytics.increment_num_users
    end

    #returns the number of radlibs created so far
    def num_radlibs
      Analytics.num_radlibs
    end

    # returns a new radlib_id
    def get_new_radlib_id
      Analytics.increment_num_radlibs
    end

    def add_super_user(uid)

      # Make sure the user counter is set in Couchbase
      initialize_document("superusers::count", 0)

      # Create the Super Users list-array
      initialize_document("superusers", { :users => [] })

      doc = get_document("superusers")
      users = doc[:users]
      unless users.include?(uid)
        users.unshift(uid)

        doc[:users] = users

        replace_document("superusers", doc)
        increase_atomic_count("superusers::count")
      end
    end

    def remove_super_user(uid)
      # Make sure the user counter is set in Couchbase
      initialize_document("superusers::count", 0)

      # Create the Super Users list-array
      initialize_document("superusers", { :users => [] })

      doc = get_document("superusers")
      users = doc[:users]
      users.delete(uid)
      doc[:users] = users

      replace_document("superusers", doc)
      decrease_atomic_count("superusers::count")
    end

    # returns the number of users signed up
    def num_superusers
      # retrieve the current user count
      count = get_document("superusers::count")

      return 0 unless count
      return count
    end

    def get_super_users
      doc = get_document("superusers")
      users = doc[:users]

      superusers = []
      users.each do |uid|
        u = User.new ({ :retrieve => true, :uid => uid })
        superusers.push(u)
      end
      superusers
    end
  end # end ClassMethods
  #####################################################################



end