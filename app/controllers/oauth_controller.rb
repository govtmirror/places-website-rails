require "oauth/controllers/provider_controller"

class OauthController < ApplicationController
  include OAuth::Controllers::ProviderController

  layout "site"

  def authorize
    foo = params["oauth_callback"] + "?oauth_token=" + params["oauth_token"] + "&addUser=http://10.147.153.193/oauth/add_active_directory_user"
    foo = URI.escape(foo, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    redirect_to "https://" + "insidemaps.nps.gov" + "/account/logon/" + "?ReturnUrl=" + foo
  end

  def access_token

    auths = ActionController::HttpAuthentication::Digest::decode_credentials(request.headers["HTTP_AUTHORIZATION"])
    @oauth_token = OauthToken.where("type = ? AND token = ? AND secret = ? AND invalidated_at IS NULL", "RequestToken", auths["oauth_token"], auths["request_token_secret"]).first
    @user = User.find(@oauth_token.user_id)
    if @oauth_token
    @access_token=AccessToken.create(:user => @user, :client_application => @oauth_token.client_application)
    @oauth_token.client_application.permissions.each do |pref|
      if @oauth_token.client_application[pref]
        @access_token.update_attribute(pref, true)
      else
        @access_token.update_attribute(pref, false)
      end
    end
      @oauth_token.update_attribute(:invalidated_at, Time.now.getutc)
      render text: "oauth_token=" + @access_token.token.to_s + "&oauth_token_secret=" + @access_token.secret.to_s + "&username=" + @user.display_name + "&userId=" + @user.id.to_s
    else
      render text: "Access Denied", status: :unauthorized
    end
  end

  def add_active_directory_user
    params.merge! JSON.parse(request.body.read)
    query = params["query"]
    if query["addUser"]
      @user = User.find_by(:email => params["userId"])
      unless @user
        # TODO: If username already exists but with a different userId (stored in email) add a number at the end
        @user = User.new(
          :email => params["userId"],
          :email_confirmation => params[:email],
          :status => "active",
          :pass_crypt => Digest::MD5.hexdigest(params["userId"]),
          :display_name => params["name"],
          :data_public => 1,
          :description => params["userId"],
          :terms_seen => true,
          :email_valid => true,
          :pass_salt => Digest::MD5.hexdigest(params["name"]),
          :terms_agreed => Time.now.getutc,
          :image_file_name => "http://www.nps.gov/npmap/tools/assets/img/places-icon.png"
        )
        if @user.invalid?
          raise ActionController::MethodNotAllowed.new
        else
          @user.save
        end
      end
      @token = OauthToken.find_by(token: query["oauth_token"])
      @token.update_attribute(:user_id, @user.id)
      @token.update_attribute(:authorized_at, Time.now.getutc)
      render :text => params["name"]
    else
      raise ActionController::MethodNotAllowed.new
    end
  end

  def login_required
    authorize_web
    set_locale
    foo = params["oauth_callback"] + "?oauth_token=" + params["oauth_token"] + "&addUser=http://10.147.153.193/oauth/add_active_directory_user"
    foo = URI.escape(foo, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    redirect_to "https://" + "insidemaps.nps.gov" + "/account/logon/" + "?ReturnUrl=" + foo
  end

  def user_authorizes_token?
    any_auth = false

    @token.client_application.permissions.each do |pref|
      if params[pref]
        @token.write_attribute(pref, true)
        any_auth ||= true
      else
        @token.write_attribute(pref, false)
      end
    end

    any_auth
  end

  def revoke
    @token = current_user.oauth_tokens.find_by_token params[:token]
    if @token
      @token.invalidate!
      flash[:notice] = t("oauth.revoke.flash", :application => @token.client_application.name)
    end
    redirect_to oauth_clients_url(:display_name => @token.user.display_name)
  end

  protected

  def oauth1_authorize
    if @token.invalidated?
      @message = t "oauth.oauthorize_failure.invalid"
      render :action => "authorize_failure"
    else
      if request.post?
        if user_authorizes_token?
          @token.authorize!(current_user)
          if @token.oauth10?
            callback_url = params[:oauth_callback] || @token.client_application.callback_url
          else
            callback_url = @token.oob? ? @token.client_application.callback_url : @token.callback_url
          end
          @redirect_url = URI.parse(callback_url) unless callback_url.blank?

          if @redirect_url.to_s.blank?
            render :action => "authorize_success"
          else
            @redirect_url.query = if @redirect_url.query.blank?
                                    "oauth_token=#{@token.token}"
                                  else
                                    @redirect_url.query +
                                      "&oauth_token=#{@token.token}"
                                  end

            unless @token.oauth10?
              @redirect_url.query += "&oauth_verifier=#{@token.verifier}"
            end

            redirect_to @redirect_url.to_s
          end
        else
          @token.invalidate!
          @message = t("oauth.oauthorize_failure.denied", :app_name => @token.client_application.name)
          render :action => "authorize_failure"
        end
      end
    end
  end
end
