DataMapper.setup(:default, "sqlite://#{Dir.pwd}/db.sqlite")

class User
  include DataMapper::Resource
  include BCrypt

  property :id, Serial, key: true
  property :email, String, length: 128, format: :email_address, unique: true, message: 'Enter valid email'
  property :phone_number, String, length: 64
  property :greeting, String, length: 2048, format: :url
  property :password, BCryptHash

  has n, :voice_messages
  has n, :active_calls

  def authenticate(attempted_password)
    # The BCrypt class, which `self.password` is an instance of, has `==` defined to compare a
    # test plain text string to the encrypted string and converts `attempted_password` to a BCrypt
    # for the comparison.
    #
    if self.password == attempted_password
      true
    else
      false
    end
  end

  def play_greeting(call)
    data = {tag: 'greeting'}
    if greeting
      data[:file_url] = greeting
    else
      data[:gender] = 'female'
      data[:locale] = 'en_US'
      data[:voice] = 'kate'
      data[:sentence] = "You have reached the voice mailbox for #{phone_number}. Please leave a message at the beep"
    end
    call.play_audio data
  end
end

class VoiceMessage
  include DataMapper::Resource
  property :id, Serial
  property :url, String, length: 2048, format: :url
  property :start_time, DateTime
  property :end_time, DateTime
  belongs_to :user, key: true
end

class ActiveCall
  include DataMapper::Resource
  property :id, String, :key => true
  belongs_to :user, key: true
end

# raise errors on save failing
DataMapper::Model.raise_on_save_failure = true

# Tell DataMapper the models are done being defined
DataMapper.finalize

# Update the database
DataMapper.auto_upgrade!

