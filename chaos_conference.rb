require "sinatra"
require "rack"
require "rack/contrib"
require "bandwidth"
require "yaml"

Call = Bandwidth::Call
Conference = Bandwidth::Conference
ConferenceMember = Bandwidth::ConferenceMember

conference_id = nil;
client = nil;

ORDINALS  = ["", "first", "second", "third", "fourth", "fifth"];
def to_ordinal_number(count)
  return "#{count}th" if count >= ORDINALS.size
  ORDINALS[count]
end
options = YAML.load(File.read("./options.yml"))

use Rack::PostBodyContentTypeParser

get "/" do
  if !options["api_token"] || !options["api_secret"] || !options["conference_number"] || !options["domain"]
    "Please fill options.yml with right values"
  else
    "This app is ready to use"
  end
end

post "/start/demo" do
  halt 400, "number is required" unless params["to"]
  callback_url = "http://#{options["domain"]}/events/#{ if conference_id  then "other_call_events" else  "first_member" end}";
  Call.create(client, {
      :from => options["conference_number"],
      :to => params["to"],
      :callback_url => callback_url,
      :recording_enabled => false
  })
  ""
end

post "/events/first_member" do
  call = Call.new({:id => params["callId"]}, client)
  case(params["eventType"])
    when "answer"
      sleep 3
      call.speak_sentence "Welcome to the conference"
    when "speak"
      return "" if params["status"] != "done" || params["tag"] == "notification"
      conference_url = "http://#{options["domain"]}/events/conference"
      conference = Conference.create(client, {
        :from => options["conference_number"],
        :callback_url => conference_url
      })
      conference.create_member({
        :callId => call.id,
        :joinTone => true,
        :leavingTone => true
      })
    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
  ""
end

post "/events/other_call_events" do
  call = Call.new({:id => params["callId"]}, client)
  case(params["eventType"])
    when "answer"
      if conference_id
        call.speak_sentence("You will be join to conference.", "conference:#{conference_id}")
      else
        call.speakSentence("We are sorry, the conference is not active.", "terminating")
      end
    when "speak"
      return "" if params["status"] != "done"
      if params["tag"] == "terminating"
        call.hangUp()
      else
        return "" if params["tag"] == "notification"
        values = params["tag"].split(":")
        id = values.last
        conference = new Conference({:id => id}, client)
        conference.create_member({
          :call_id => call.id,
          :join_tone => true
        })
      end
    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
  ""
end

post "/events/conference" do
  case (params["eventType"])
    when "conference"
      conference_id = if ev.status == "created" then params["conferenceId"] else nil end
    when "conference-member"
      return "" if (params["state"] != "active" || params["activeMembers"] < 2) #don't speak anything to conference owner (first member)
      member = ConferenceMember.new({:id => params["memberId"], :conference_id => params["conference_id"]}, client)
      member.playAudio({
        :gender => "female",
        :locale => "en_US",
        :voice => "kate",
        :sentence => "You are the #{to_ordinal_number(params["activeMembers"])} caller to join the conference",
        :tag => "notification"
      })
    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
end

client = Bandwidth::Client.new(options)

set :bind, "0.0.0.0"
set :port, (ENV["PORT"] || "3000").to_i
