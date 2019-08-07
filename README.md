Revops Webhook Server - Ruby Example
-----------

This is an example of using integrating the revops webhooks with zuora.

Installation
---------------

To work on the sample code, you'll need to clone your project's repository to your local computer. If you haven't, do that first. You can find a guide [here](https://help.github.com/articles/cloning-a-repository/).

1. Ensure you are using a recent version of Ruby. Latest stable is 2.6.3 as of 8/7/2019. We recommend using [rbenv](https://github.com/rbenv/rbenv) for managing your ruby versions.

2. Install bundle

        gem install bundler

3. Install Ruby dependencies for this service

        bundle install

4. Edit the `.env` configuration file by supplying your zuora login credentials

## Running the server

You can start the server with: 

        ruby webhook.rb

This app uses [Sinatra](http://sinatrarb.com/) 

The following options are available:
```
ruby webhooks.rb [-h] [-x] [-q] [-e ENVIRONMENT] [-p PORT] [-o HOST] [-s HANDLER]

Options are:

-h # help
-p # set the port (default is 4567)
-o # set the host (default is 0.0.0.0)
-e # set the environment (default is development)
-s # specify rack server/handler (default is thin)
-q # turn on quiet mode for server (default is off)
-x # turn on the mutex lock (default is off)
```

## License

MIT
