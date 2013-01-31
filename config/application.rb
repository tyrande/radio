require 'sinatra/base'
require "sinatra/cookies"
require 'logger'
require 'digest/sha1'
require 'rexml/document'
require 'json'
require 'net/http'
require 'haml'
require 'redis'
require 'models/user'

class Radio < Sinatra::Base
  helpers Sinatra::Cookies
  
  configure do
    Logger.class_eval { alias :write :"<<" } unless Logger.instance_methods.include? "write" 
    set :logger, Logger.new('./log/access.log')
    set :error_logger, Logger.new('./log/error.log')
    $stderr.reopen(File.new('./log/error.log', "a+"))
    use Rack::CommonLogger, logger
    
    Redis.current = Redis.new(:host => '127.0.0.1', :port => '6379', :db => '6') 

    if defined?(PhusionPassenger)
      PhusionPassenger.on_event(:starting_worker_process) do |forked|
        if forked
          Redis.current.client.disconnect
          Redis.current = Redis.new(:host => '127.0.0.1', :port => '6379', :db => '6')
        end
      end
    end
    
    #set :protection, :except => :frame_options
    disable :protection
    set :haml, {:format => :html5 }
  end
  
  before do
    cookies[:_token] = Digest::SHA1.hexdigest("radio#{Time.now.to_i}session") unless cookies[:_token]
  end

  get '/' do
    u = User.find_by_token(cookies[:_token])
    redirect to('/login') unless u
    haml :devices, :locals => { :devices => u.devices, :user => u, :cur => 'list', :did => "" }
  end

  get '/login' do
    u = User.find_by_token(cookies[:_token])
    redirect to('/devices/list') if u
    haml :login, :layout => false
  end

  post '/users' do
    u = User.find_by_name(params[:name].strip.downcase)
    redirect to('/login') unless u and u.auth(params[:password])
    Redis.current.setex("radio:sessions:#{cookies[:_token]}", 604800, u.id)
    redirect to('/devices/list')
  end

  get '/logout' do
    cookies[:_token] = Digest::SHA1.hexdigest("radio#{Time.now.to_i}session")
    redirect to('/login')
  end

  get '/devices/list' do
    u = User.find_by_token(cookies[:_token])
    redirect to('/login') unless u
    haml :devices, :locals => { :devices => u.devices, :user => u, :cur => 'list', :did => "" }
  end
  
  get '/devices/pair' do
    u = User.find_by_token(cookies[:_token])
    redirect to('/login') unless u
    _pid = get_pair(u)
    haml :pair, :locals => { :devices => u.devices, :user => u, :cur => 'pair', :did => "", :pair_id => "pair:#{_pid.length}$#{_pid}" }
  end
  
  get '/devices/show/:id' do
    u = User.find_by_token(cookies[:_token])
    redirect to('/login') unless u
    halt unless Redis.current.sismember("radio:#{u.id}:devices", params[:id])
    _attr = Redis.current.get "radio:devices:#{params[:id]}" 
    haml :device, :locals => { :devices => u.devices, :user => u, :cur => 'list', :did => params[:id], :attr => _attr }
  end
  
  post '/devices/update_attr/:id' do
    u = User.find_by_token(cookies[:_token])
    redirect to('/login') unless u
    halt unless Redis.current.sismember("radio:#{u.id}:devices", params[:id])
    _attr = request.body.read.to_s
    Redis.current.set "radio:devices:#{params[:id]}", _attr
    [200, 'ok']
  end
  
  post '/devices/create_pair/:id' do
    u = User.find(params[:pair_key][6..-1])
    if params[:pair_key] == get_pair(u)
      Redis.current.sadd "radio:#{u.id}:devices", params[:id]
      Redis.current.set "radio:devices:#{params[:id]}", { :status => 0 }.to_json
      [200, 'ok']
    else
      [200, 'error']
    end
  end
  
  get '/devices/get_attr/:id' do
    _attr = Redis.current.get "radio:devices:#{params[:id]}"
    [200, _attr]
  end
  
  def log_error_ex(error_)
    settings.error_logger.error("#{env['REMOTE_ADDR']} #{error_.class.to_s} : #{error_.message.to_s}\n#{error_.backtrace[0, 10].join("\n")}")
  end

  def get_pair(u)
    _token = Redis.current.get "radio:#{u.id}:token"
    unless _token
      _token = "#{Digest::SHA1.hexdigest("1#{Time.now.to_i}radio")[0, 6]}#{u.id}"
      Redis.current.set "radio:#{u.id}:token", _token
    end
    return _token
  end

  def current_user(session_token_)
    Redis.current.get("radio:sessions:#{session_token_}").to_i
  end
end
