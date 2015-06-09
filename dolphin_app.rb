require "sinatra"
require "rack"
require "rack/contrib"
require "ruby-bandwidth"
require "yaml"

Call = Bandwidth::Call
Bridge = Bandwidth::Bridge

client = nil

options = YAML.load(File.read("./options.yml"))

use Rack::PostBodyContentTypeParser

get "/" do
    if !options["api_token"] || !options["api_secret"] || !options["caller"] || !options["bridge_callee"] || !options["domain"]
      "Please fill options.yml with right values"
    else
      "This app is ready to use: Dolphin App"
    end
end

post "/start/demo" do
  halt 400, "number is required" unless params["to"]
  callback_url = "http://#{options["domain"]}/events/demo";
  Call.create(client, {
      :from => options["caller"],
      :to => params["to"],
      :callback_url => callback_url,
      :recording_enabled => false
  })
end

post "/events/demo" do
  call = Call.new({:id => params["callId"]}, client)
  case(params["eventType"])
    when "answer"
      sleep 3
      call.speak_sentence("hello flipper", "hello-state")
    when "speak"
      return "" unless  params["status"] == "done"
      case(params["tag"])
        when "gather_complete"
          Call.create(client, {
              :from => options["caller"],
              :to => options["bridge_callee"],
              :callback_url => "http://#{options["domain"]}/events/bridged",
              :tag => "other-leg:#{call.id}"
          })
        when "terminating"
          call.hangup()
        when "hello-state"
          call.play_audio({
            :file_url => "http://#{options["domain"]}/dolphin.mp3",
            :tag => "dolphin-state"
          })
      end
    when "dtmf"
      if params["dtmfDigit"][0] == "1"
        call.speak_sentence("Please stay on the line. Your call is being connected.", "gather_complete")
      else
        call.speak_sentence("This call will be terminated", "terminating")
      end
    when  "playback"
      return "" unless params["status"] == "done"
      if params["tag"] == "dolphin-state"
        call.create_gather({
          :max_digits => 2,
          :terminating_digits => "*",
          :inter_digit_timeout => "3",
          :prompt => {
              :sentence => "Press 1 to speak with the fish, press 2 to let it go",
              :loop_enabled => false,
              :voice => "Kate"
          },
          :tag => "gather_started"
        })
      end

    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
end

post "/events/bridged" do
  call = Call.new({:id => params["callId"]}, client)
  values = (params["tag"] || "").split(":")
  other_call_id = values[1]
  case (params["eventType"])
    when "answer"
      sleep 3
      call.speak_sentence("You have a dolphin on line 1. Watch out, he's hungry!", "warning:#{other_call_id}")
    when "speak"
      return "" unless params["status"] == "done"
      if values[0] == "warning"
        Bridge.create(client, {
          :callIds => [other_call_id]
        })
      end
    when "hangup"
      call.id = other_call_id
      if params["cause"] == "CALL_REJECTED"
        call.speak_sentence("We are sorry, the user is reject your call", "terminating")
      else
        call.hangup()
      end
    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
end

opts = {}
options.each do |k,v|
  opts[k.to_sym] = v
end

client = Bandwidth::Client.new(opts)

set :bind, "0.0.0.0"
set :port, (ENV["PORT"] || "3000").to_i
set :public_folder, "public"
