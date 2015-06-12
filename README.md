ruby-bandwidth-example
======================

4 demos of Catapult API

Dolphin app demonstrates how to play audio, speak text to callers, and gather DTMF from the caller.

Chaos Conference is a very simple conferencing app that joins users to a conference by making outbound calls to each attendee

Sip App is simple application which allows to make calls directly to sip account, redirect outgoing calls from sip account to another number, redirect incoming calls from specific number to sip account. Also this application demonstrate how to receive/create an application, domain, endpoint, buy phone numbers.

Transcription App is simple voice mail app which sends email notifications to user with transcripted message text. It demonstrates how to make calls, handle incoming calls to registered number, handle events, tune on call recording, create a transcription for recording. Also it shows how to register an application on catapult and buy new phone number.


Before run them fill config file `options.yml` with right values.
Option `conferenceNumber` is required for chaos confernce only.
Options `caller` and `bridgeCallee` are used by dolphin app only.
Option `domain` should contains host name (and port) which will be used to access to the server from external network.

Warning: Transcription App has own options.yml file. Fill it too if you are going to run this app.i Don't forget run `bundler install` there too

### How to run

Install required gems

```
bundler install
```

Run Chaos conference demo as

```
ruby -rubygems  chaos_conference.rb
```

Run Dolphin app demo as

```
ruby -rubygems  dolphin_app.rb
```

Run Sip app demo as

```
ruby -rubygems sip_app.rb
```

Run Transcription app demo as

```
cd transcription_app

ruby -rubygems app.rb

#or with rackup

rackup config.ru 
```

Use environment variable `PORT` to change default port (3000)

For Dolphin app and Chaos conference start incoming call from command line:

```console
curl -d '{"to": "+YOUR-NUMBER"}' http://YOUR-DOMAIN/start/demo --header "Content-Type:application/json"
```
For Chaos conference run this command again with another number to add  it to the conference (first member is owner)

For Sip app open home page in browser first (http://domain) and follow instructions on it

### Deploy on heroku

Create account on [Heroku](https://www.heroku.com/) and install [Heroku Toolbel](https://devcenter.heroku.com/articles/getting-started-with-ruby#set-up) if need.

Open `Procfile` in text editor and select which demo you would like to deploy.

```
# for Chaos Conference
web: ruby -rubygems ./chaos_conference.rb

# for Dolpin App
web: ruby -rubygems ./dolphin_app.rb

# for Sip App
web: ruby -rubygems ./sip_app.rb

# for Transcription App
web: cd transcription_app && ruby -rubygems ./app.rb
```


Then open `options.yml` and fill it with valid values (except `domain` and `base_url`).

Commit your changes.

```
git add .
git commit -a -m "Deployment"
```

Run `heroku create` to create new app on Heroku and link it with current project.

Change option `domain` (or `base_url` for TranscriptionApp)  in options.yml by assigned by Heroku value (something like XXXX-XXXXX-XXXX.heroku.com). Commit your changes by `git commit -a`. 

Run `git push heroku master` to deploy this project.

Run `heroku open` to see home page of the app in the browser

### Open external access via ngrock

As alternative to deployment to external hosting you can open external access to local web server via [ngrock](https://ngrok.com/).

First instal ngrock on your computer. Run ngrock by


```
ngrok http 3000 #you can use another free port if need 
```

You will see url like http://XXXXXXX.ngrok.io on console output. Open `options.yml` and fill value `domain` (or `base_url` for TranscriptionApp) by value from console (i.e. like XXXXXXX.ngrock.io). Save changes and run demo app by


```
# for Chaos Conference
PORT=3000 ruby -rubygems ./chaos_conference.rb

# for Dolpin App
PORT=3000 ruby -rubygems ./dolphin_app.rb

# for Sip App
PORT=3000 ruby -rubygems ./sip_app.rb

# for Transcription App

PORT=3000 ruby -rubygems ./app.rb

#or with rackup

rackup config.ru -p 3000

```
