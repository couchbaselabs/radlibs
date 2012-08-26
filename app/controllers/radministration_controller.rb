class RadministrationController < ApplicationController
  include ModelGlobal

  def index
    @site_analytics = Analytics.retrieve_all_docs
    Rails.logger.debug(@site_analytics.inspect)
  end

  def users
    @user_count = Analytics.num_users
    @superuser_count = ModelGlobal.num_superusers
    @superusers = ModelGlobal.get_super_users

    keys = []
    @user_count.downto(1) do |i|
      keys.push("u::#{i + Yetting.user_count_start}")
    end
    @users = ModelGlobal.get_multiple_users_by_uid(keys)
  end

  def radlibs

  end

  def application_settings

  end
end
