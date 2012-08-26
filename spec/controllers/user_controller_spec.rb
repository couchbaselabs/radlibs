require 'spec_helper'

describe UserController do

  describe "GET 'authenticate'" do
    it "returns http success" do
      get 'authenticate'
      response.should be_success
    end
  end

  describe "GET 'signup'" do
    it "returns http success" do
      get 'signup'
      response.should be_success
    end
  end

  describe "GET 'get_started'" do
    it "returns http success" do
      get 'get_started'
      response.should be_success
    end
  end

end
