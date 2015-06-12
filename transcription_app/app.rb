require 'bundler'
require 'yaml'
Bundler.require

require './model'

$options = YAML.load(File.read("./options.yml"))

opts = {}
$options.each do |k,v|
  opts[k.to_sym] = v
end

Bandwidth::Client.global_options = opts

Mail.defaults do
    delivery_method :smtp, opts[:mail]
end

Warden::Strategies.add(:password) do
  def valid?
     params['email'] && params['password']
  end

  def authenticate!
    user = User.first(email: params['email'])

    if user.nil?
      throw(:warden, message: "The user with such email does not exist.")
    elsif user.authenticate(params['password'])
      success!(user)
    else
      throw(:warden, message: "The email and password combination")
    end
  end
end

class TranscriptionApp < Sinatra::Base
  use Rack::PostBodyContentTypeParser
  enable :sessions
  register Sinatra::Flash
  set :session_secret, "transcriptionsecret"
  set :public_folder, File.dirname(__FILE__) + '/public'
  use Warden::Manager do |config|
    config.serialize_into_session{|user| user.id }

    config.serialize_from_session{|id| User.get(id) }

    config.scope_defaults :default,
      strategies: [:password],
      action: 'auth/unauthenticated'
    config.failure_app = self
  end

  Warden::Manager.before_failure do |env,opts|
    env['REQUEST_METHOD'] = 'POST'
  end


  get '/auth/login' do
    erb :login
  end

  post '/auth/login' do
    env['warden'].authenticate!

    flash[:success] = env['warden'].message

    if session[:return_to].nil?
      redirect '/'
    else
      redirect session[:return_to]
    end
  end

  get '/auth/register' do
    erb :register
  end

  post '/auth/register' do
    begin
      if !params['password']
        raise 'Missing password'
      end
      if params['repeat_password'] != params['password']
        raise 'Passwords are mismatched'
      end

      number = Bandwidth::AvailableNumber.search_local({:city => 'Cary', :state => 'NC', :quantity => 1}).first[:number]
      Bandwidth::PhoneNumber.create(:number => number, :application_id => $application_id)
      User.create(email: params['email'], password: params['password'], phone_number: number)
      env['warden'].authenticate!
      if session[:return_to].nil?
        redirect '/'
      else
        redirect session[:return_to]
      end
    rescue DataMapper::SaveFailureError => e
      flash[:error] = (e.resource.errors.values.select {|v| v[0]}).join('\n')
      redirect '/auth/register'
    rescue Exception => e
      flash[:error] = e.message
      redirect '/auth/register'
    end
  end

  get '/auth/logout' do
    env['warden'].raw_session.inspect
    env['warden'].logout
    flash[:success] = 'Successfully logged out'
    redirect '/auth/login'
  end

  post '/auth/unauthenticated' do
    session[:return_to] = env['warden.options'][:attempted_path] if session[:return_to].nil?

    flash[:error] = env['warden.options'][:message] || "You must log in"
    redirect '/auth/login'
  end

  get '/' do
    env['warden'].authenticate!
    erb :index
  end

  post '/call' do
    warden = env['warden']
    warden.authenticate!
    Bandwidth::Call.create(from: warden.user.phone_number , to: params['phone_number'], callback_url:"#{$options['base_url']}/events/admin")
    flash[:info] = 'Please answer a call'
    redirect '/'
  end

  post '/events/admin' do
    puts params
    call = Bandwidth::Call.new({:id => params["callId"]})
    case(params['eventType'])
       when 'answer'
         user = User.first(phone_number: params['from'])
         if user
           ActiveCall.create(id: call[:id], user_id: user.id)
           sleep 2
           main_menu(call)
         else
           call.hangup()
         end
       when 'hangup'
         active_call = ActiveCall.first(id: call[:id])
         active_call.destroy() if active_call
       when 'playback', 'speak'
         return unless params['status'] == 'done'
         tags = (params['tag'] || '').split(':')
         active_call = ActiveCall.first(id: params['callId'])
         if active_call
           user = active_call.user
         else
           return
         end
         case tags[0]
           when 'start-recording'
             call.recording_on()
             call.create_gather(tag: 'recording', inter_digit_timeout: 30, max_digits: 30, terminating_digits: '#')
           when 'listen-to-recording'
             user.play_greeting(call)
           when 'remove-recording'
             user.greeting = nil
             user.save()
             voice_mail_menu(call)
           when 'stop-recording', 'greeting'
             voice_mail_menu(call)
           when 'main-menu'
             main_menu(call)
           when 'voice-message-date'
             index = tags[1].to_i
             call.play_audio(file_url: user.voice_messages[index].url, tag: "voice-message-url:#{index}")
           when 'voice-message-url'
             index = tags[1].to_i
             sleep(1.5)
             voice_message_menu(call, index)
         end
       when 'recording'
         return unless params['state'] == 'complete'
         active_call = ActiveCall.first(id: params['callId'])
         if active_call
           user = active_call.user
           recording = Bandwidth::Recording.get(params['recordingId'])
           user.greeting = recording[:media]
           user.save()
         end
       when 'gather'
         return unless params['state'] == 'completed'
         active_call = ActiveCall.first(id: params['callId'])
         return unless active_call
         user = active_call.user
         tags = params['tag'].split(':')
         case tags[0]
           when 'recording'
             call.recording_off()
             call.speak_sentence('Your greeting has been recorded. Thank you.', 'stop-recording')
           when 'main-menu'
             case params[:digits]
               when '1'
                 play_voice_mail_message(user, call, user.voice_messages.length-1)
               when '2'
                 voice_mail_menu(call)
               else
                 main_menu(call)
             end
           when 'voice-mail-menu'
             case params[:digits]
               when '0'
                 main_menu(call)
               when '1'
                 call.speak_sentence('Say your greeting now. Press # to stop recording.', 'start-recording')
               when '2'
                 call.speak_sentence('Your greating', 'listen-to-recording')
               when '3'
                 call.speak_sentence('Your greating will be set to default', 'remove-recording')
               else
                 voice_mail_menu(call)
             end
           when 'voice-message-menu'
             index = tags[1].to_i
             case params[:digits]
               when '0'
                 main_menu(call)
               when '1'
                 play_voice_mail_message(user, call, index-1)
               when '2'
                 user.voice_messages[index].destroy()
                 user.voice_messages.reload()
                 play_voice_mail_message(user, call, index-1)
               when '3'
                 play_voice_mail_message(user, call, index)
               else
                 voice_message_menu(call, index)
             end
         end

    end
    ''
  end

  post '/events/externalCall' do
    puts params
    call = Bandwidth::Call.new(id: params["callId"])
    case(params['eventType'])
      when 'incomingcall'
        user = User.first(phone_number: params['to'])
        if user
          ActiveCall.create(id: call[:id], user_id: user.id)
          call.answer_on_incoming()
        else
          call.reject_incoming()
        end
      when 'answer'
        active_call = ActiveCall.first(id: params['callId'])
        unless active_call
          call.hangup()
          return
        end
        sleep(1)
        active_call.user.play_greeting(call)
      when 'hangup'
        call_id = params['callId']
        timeout = Thread.new(Time.now + 600) do |end_time|
          while Time.now < end_time
            Thread.pass
          end
          active_call = ActiveCall.first(id: call_id)
          active_call.destroy() if active_call
        end
        timeout.join()
      when 'speak', 'playback'
        return unless params['status'] == 'done'
        case params['tag']
          when 'greeting'
            #play beep before recording
            call.play_audio(file_url: "#{$options['base_url']}/beep.mp3", tag: 'start-recording')
          when 'start-recording'
            #start recording of call after 'beep' (with transcription of result)
            call.update(transcription_enabled: true, recording_enabled: true)
            #press any key to stop recording (and call too)
            call.create_gather(tag: 'stop-recording', inter_digit_timeout: 30, max_digits: 1)
        end
      when 'gather'
        return unless params['state'] == 'completed'
        #make hangup on press any key
        if params['tag'] == 'stop-recording'
          call.hangup()
        end
      when 'transcription'
        return unless params['state'] == 'completed' || params['status'] == 'completed'
        #call was recorded and transcription was completed here
        recording = Bandwidth::Recording.get(params['recordingId'])
        call_id = recording[:call].split('/').last
        call = Bandwidth::Call.get(call_id)
        active_call = ActiveCall.first(id: call_id)
        raise "Missing active call with id #{call_id}" unless active_call
        user = active_call.user
        from = call[:from]
        #save voice message in db
        VoiceMessage.create(url: recording[:media], start_time: recording[:start_time], end_time: recording[:end_time], user_id: user.id)
        #and send email notification to user
        Mail.deliver do
          to user.email
          from $options['mail']['from']
          subject "TranscriptionApp - new voice message from #{from}"
          body """
          <p>You received a new voice message from <b>#{from}</b> at #{recording[:start_time].strftime('%D %r')}:</p>
          <p>#{params['text']}</p>
          """
        end
    end
    ''
  end

  def menu(call, prompt, tag)
    call.create_gather(
      tag: tag,
      max_digits: 1,
      prompt: {
        locale: 'en_US',
        gender: 'female',
        sentence: prompt,
        voice: 'kate',
        bargeable: true,
        loop_enabled: false
      }
    )
  end

  def main_menu(call)
     menu call, 'Press 1 to listen to your voicemail. Press 2 to record a new greeting.', 'main-menu'
  end

  def voice_mail_menu(call)
     menu call, 'Press 1 to record a greeting.  Press 2 to listen to the greeting. Press 3 to use the default greeting. Press 0 to go back.', 'voice-mail-menu'
  end

  def voice_message_menu(call, index)
     menu(call, 'Press 1 to go to the next voice mail. Press 2 to delete this voice mail and go to the next one.' +
            'Press 3 to repeat this voice mail again. Press 0 to go back to main menu.',  "voice-message-menu:#{index}")
  end

  def play_voice_mail_message(user, call, index)
    return call.speak_sentence('You have no voice messages', 'main-menu') if index < 0
    message = user.voice_messages[index]
    call.speak_sentence(message.start_time.strftime('%D %r'),  "voice-message-date:#{index}")
  end

  APPLICATION_NAME = 'RubyTranscriptionApp'
  app = (Bandwidth::Application.list().select {|a| a[:name] == APPLICATION_NAME}).first
  app = Bandwidth::Application.create(name: APPLICATION_NAME, auto_answer: false, incoming_call_url: "#{$options['base_url']}/events/externalCall")
  $application_id = app[:id]
end

if __FILE__ == $0 || __FILE__ == $1
  #if this file executes as main script
  TranscriptionApp.run!()
end
