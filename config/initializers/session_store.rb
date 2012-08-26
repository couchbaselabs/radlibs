# Be sure to restart your server when you modify this file.
require 'action_dispatch/middleware/session/dalli_store'

Rails.application.config.session_store :dalli_store,
                                       :memcache_server => Yetting.couchbase_servers,
                                       :namespace => '_radlibs_session',
                                       :key => '_radlibs_session',
                                       :expire_after => Yetting.session_duration.minutes

# Remove Default cookie session store
# Radlibs::Application.config.session_store :cookie_store, key: '_radlibs_session'

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rails generate session_migration")
# Radlibs::Application.config.session_store :active_record_store
