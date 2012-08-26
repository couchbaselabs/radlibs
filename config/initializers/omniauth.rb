Rails.logger.debug("Facebook: #{Yetting.facebook_key}")

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :facebook, Yetting.facebook_key, Yetting.facebook_secret,
           { :client_options => {:ssl => {:ca_path => "/etc/ssl/certs"}},
             :scope => Yetting.facebook_scope,
             :display => 'popup' }
end