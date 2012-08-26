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
require 'couchbase'
require 'map'

module DocumentStore
  include Term::ANSIColor

  COUCH = Couchbase.new(Yetting.couchbase)

  #### INSTANCE METHODS

  def document_exists?(key)
    return nil unless key
    DocumentStore.document_exists?(key)
  end

  def initialize_document(key, value, args={})
    return nil unless key
    DocumentStore.initialize_document(key, value, args)
  end

  def create_document(key, value, args={})
    return nil unless key
    DocumentStore.create_document(key, value, args) # => if !quiet, Generates Couchbase::Error::KeyExists if key already exists
  end

  def replace_document(key, value, args = {})
    return nil unless key
    DocumentStore.replace_document(key, value, args)
  end

  def get_document(key, args = {})
    return nil unless key
    DocumentStore.get_document(key, args)
  end

  def get_documents(keys = [], args = {})
    return nil unless keys || keys.empty?
    DocumentStore.get_documents(keys, args)
  end

  def delete_document(key, args={})
    return nil unless key
    DocumentStore.delete_document(key, args)
  end

  # @param args :amount => Fixnum||Integer, increases by that
  def increase_atomic_count(key, args={})
    return nil unless key
    DocumentStore.increase_atomic_count(key, args)
  end

  def decrease_atomic_count(key, args={})
    return nil unless key
    DocumentStore.decrease_atomic_count(key, args)
  end

  # preferred way is to use create/replace to make sure there are no collisions
  def force_set_document(key, value, args={})
    return nil unless key
    DocumentStore.force_set_document(key, value, args)
  end



  # end Instance Methods
  #####################################################################
  #### CLASS METHODS

  class << self

    def delete_all_documents!
      COUCH.flush
    end

    def document_exists?(key)
      return nil unless key

      # Save quiet setting
      tmp = COUCH.quiet

      # Set quiet to be sure
      COUCH.quiet = true

      doc = COUCH.get(key)

      # Restore quiet setting
      COUCH.quiet = tmp

      !doc.nil?
    end
    
    # can consume exception to reduce trips by 1 on new
    def initialize_document(key, value, args={})
      return nil unless key
      COUCH.quiet = false
      doc = DocumentStore.get_document( key )
      (value.is_a?(Fixnum) || value.is_a?(Integer) ? COUCH.set( key, value ) : COUCH.add( key, value )) unless doc
    rescue Exception => e
    end

    def create_document(key, value, args={})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      COUCH.add(key, value, args) # => if !quiet, Generates Couchbase::Error::KeyExists if key already exists
    end

    def replace_document(key, value, args = {})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      COUCH.replace(key, value) # => if !quiet, Generates Couchbase::Error::NotFound if key doesn't exist
    end

    def get_document(key, args = {})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      doc = COUCH.get(key, args)
      doc.is_a?(Hash) ? Map.new(doc) : doc
    end

    def get_documents(keys = [], args = {})
      return nil unless keys || keys.empty?
      values = COUCH.get(keys, args)

      if values.is_a? Hash
        tmp = []
        tmp[0] = values
        values = tmp
      end
      # convert hashes to Map (subclass of Hash with *better* indifferent access)
      values.each_with_index do |v, i|
        values[i] = Map.new(v) if v.is_a? Hash
      end

      values
    end

    def delete_document(key, args={})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      COUCH.delete(key)
    end

    def increase_atomic_count(key, args={})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      COUCH.incr(key, args[:amount] || 1)
    end

    def decrease_atomic_count(key, args={})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      COUCH.decr(key, args[:amount] || 1)
    end

    # preferred way is to use create/replace instead of this to make sure there are no collisions
    def force_set_document(key, value, args={})
      return nil unless key
      COUCH.quiet = args[:quiet] || true
      COUCH.set(key, value, args)
    end

  end# end ClassMethods

  #####################################################################




end