### This is a Ruby on Rails Example

## Prerequisites

- You have a Bandwidth account
- You have at least one Bandwidth Phone Number allocated to your account

Tutorial for buying and allocating a phone number

http://ap.bandwidth.com/docs/how-to-guides/buying-new-phone-numbers/

## Getting Started & Installing on Heroku

Clone and create a new heroku app

```
$ git clone https://github.com/bandwidthcom/ruby-bandwidth-example.git
$ cd ruby-bandwidth-example/anonymous-two-way-sms
$ bundle
$ rake db:migrate
$ rails s
```

Should be running locally now, you can push to Heroku

```
$ git init
$ git add -A
$ git commit -m "Init"
$ heroku create
$ git push heroku master
$ heroku run rake db:migrate
$ heroku config:set BW_USER_ID='u-your_user_id_found_in_account_tab'
$ heroku config:set BW_TOKEN='t-your_token_found_in_account_tab'
$ heroku config:set BW_SECRET='your_secret_found_in_account_tab'
```

## Update Your Bandwidth Account For Incoming SMS

Login to your Bandwidth account and set-up an application and add your phone number for your phone number to send inbound text messages to heroku

http://ap.bandwidth.com/docs/how-to-guides/configuring-apps-incoming-messages-calls/

Open Heroku and Set-Up Your Phone Number
```
$ heroku open
```

Set the Bw phone number = the phone number you configured above

Set the agent phone number to your own mobile phone where you want to recieve messages

Now you can test by having anyone send SMS to the BW phone number.

