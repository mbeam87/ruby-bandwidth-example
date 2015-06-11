require "sinatra"
require "rack"
require "rack/contrib"
require "ruby-bandwidth"
require "yaml"

Call = Bandwidth::Call
Bridge = Bandwidth::Bridge
Application = Bandwidth::Application
PhoneNumber = Bandwidth::PhoneNumber
AvailableNumber = Bandwidth::AvailableNumber
Domain = Bandwidth::Domain

APPLICATION_NAME = "SipApp Demo"
DOMAIN_NAME = "sip-app"

client = nil
sip_uri = nil, caller = nil, phone_number_for_incoming_calls = nil
options = YAML.load(File.read("./options.yml"))

DOMAIN_NAME = options["domain_name"]

use Rack::PostBodyContentTypeParser

# home page
get "/" do
    if !options["api_token"] || !options["api_secret"] || !options["domain"] || !options["user_id"]
      "Please fill options.yml with right values"
    else
      callback_url = "http://#{options["domain"]}/events/calls"
      application = (Application.list(client).select {|a| a.name == APPLICATION_NAME}).first ||
          Application.create(client, {:name => APPLICATION_NAME, :incoming_call_url => callback_url, :auto_answer => false})
      numbers = (PhoneNumber.list(client).select {|p| p.respond_to?(:application) and p.application.end_with?("/#{application.id}")})
      if numbers.size < 2
        available_numbers = AvailableNumber.search_local(client, {:city => "Cary", :state => "NC", :quantity => 2})
        numbers = available_numbers.map {|n| PhoneNumber.create(client, {:number => n[:number], :application_id => application.id})}
      end
      caller = numbers[0].number
      phone_number_for_incoming_calls = numbers[1].number
      domain = (Domain.list(client).select {|d| d.name == DOMAIN_NAME}).first ||
          Domain.create(client, :name => DOMAIN_NAME, :description => APPLICATION_NAME)
      endpoint = (domain.get_endpoints().select {|p| p.name == USER_NAME && p.application_id == application.id}).first ||
          domain.create_endpoint(:name => USER_NAME, :description => "#{USER_NAME} mobile client", :application_id => application.id,
          :domain_id => domain.id, :enabled => true, :credentials => {:password => "1234567890"})
      sip_uri = endpoint.sip_uri
      """
      This app is ready to use<br/>
      Please configure your sip phone with account <b>#{endpoint.credentials[:username]}</b>, server <b>#{endpoint.credentials[:realm]}</b> and password <b>1234567890</b>.
      Please check if your sip client is online.<br/>
      <ol>
       <li>Press this button to check incoming call to sip client directly <form action=\"/callToSip\" method=\"POST\"><input type=\"submit\" value=\"Call to sip client\"></input></form></li>
       <li>Call from sip client to any number. Outgoing call will be maden from <b>#{caller}</b></li>
       <li>Call from any phone (except sip client) to <b>#{phone_number_for_incoming_calls}</b>. Incoming call will be redirected to sip client.</li>
     </ol>
      """
    end
end


#call to sip client
post "/callToSip" do
  Call.create(client, {
      :from => caller,
      :to => sip_uri,
      :callback_url => "http://#{options["domain"]}/events/demo",
      :recording_enabled => false
  })
  "Please receive a call from sip account"
end

#event handler od direct cal to sip client
post "/events/demo" do
  call = Call.new({:id => params["callId"]}, client)
  case(params["eventType"])
    when "answer"
      call.speak_sentence("hello sip client")
    when "speak"
      return "" unless  params["status"] == "done"
      call.hangup()
    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
end

#handler of all calls
post "/events/calls" do
  call = Call.new({:id => params["callId"]}, client)
  case(params["eventType"])
    when "incomingcall"
      callback_url = "http://#{options["domain"]}/events/bridged"
      if params["from"] == sip_uri
        puts("Call from sip client")
        call.answer_on_incoming()
        Call.create(client, {
          :from => caller,
          :to => params["to"],
          :callback_url => callback_url,
          :tag => params["callId"]
        })
      else
        if params["to"] == phone_number_for_incoming_calls
          puts("Incoming call to #{phone_number_for_incoming_calls}")
          call.answer_on_incoming()
          Call.create(client, {
            :from => caller,
            :to => sip_uri,
            :callback_url => callback_url,
            :tag => params["callId"]
          })
        end
      end
    else
      puts "Unhandled event type #{params["eventType"]} for #{request.url}"
  end
end


#handler of bridged calls
post "/events/bridged" do
  case (params["eventType"])
    when "answer"
      Bridge.create(client, {:call_ids => [params["callId"], params["tag"]]})
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
