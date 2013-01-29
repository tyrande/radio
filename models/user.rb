class User
  attr_accessor :id
  def self.create(name_, pwd_)
    _uid = Redis.current.incr 'radio:count:users'
    Redis.current.set("radio:users:#{Digest::SHA1.hexdigest(name_)}", _uid)
    Redis.current.hset("radio:users:#{_uid}:intro", 'id', _uid)
    Redis.current.hset("radio:users:#{_uid}:intro", 'name', name_)
    Redis.current.hset("radio:users:#{_uid}:intro", 'password', Digest::SHA1.hexdigest(pwd_))
    true
  end
  
  def self.find(id_)
    return nil if 1 > id_.to_i or id_.to_i > Redis.current.get('radio:count:users').to_i
    u = User.new
    u.id = id_.to_i
    return u
  end
  
  def self.find_by_name(name_)
    self.find Redis.current.get("radio:users:#{Digest::SHA1.hexdigest(name_)}").to_i
  end
  
  def self.find_by_token(token_)
    self.find Redis.current.get("radio:sessions:#{token_}").to_i
  end
  
  def intro; @intro ||= Redis.current.hgetall("radio:users:#{id}:intro"); end
  
  def name; intro['name']; end
  
  def auth(pwd_)
    return false unless 0 < id
    _intro = Redis.current.hgetall("radio:users:#{id}:intro")
    return false unless Digest::SHA1.hexdigest(pwd_) == _intro['password']
    return true
  end
  
  def devices
    _devices = []
    Redis.current.smembers("radio:#{self.id}:devices").each do |did|
      _devices << { :id => did, :attr => Redis.current.get("radio:devices:#{did}") }
    end
    return _devices
  end
end