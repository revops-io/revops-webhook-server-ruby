# MIT No Attribution

# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'dotenv/load'
require 'sinatra'
require 'sinatra/reloader'
require 'zuora_api'
require 'json'
require 'pp'
require 'logger'
require_relative 'zuora_helpers'
Rails.logger = Logger.new(STDOUT)

# Fail fast if our .env file config is not set
unless ENV['ZUORA_PASSWORD'] && ENV['ZUORA_PASSWORD'].length > 7
  warn <<~EOF
    Must set the ZUORA config in the `.env` file before running this server.
  EOF
  exit(1)
end

get '/' do
  body = "<h1>Congrats on starting the journey to connect Zuora to RevOps!</h1>
  <h2>Point your webhook to: %s</h2>"

  return body % [request.env['REQUEST_URI']]
end

post '/' do
  content_type :json

  # Handle the incoming webhook request body
  @request_payload = JSON.parse(request.body.read)
  deal = @request_payload['deal']
  deal_status = deal['status']
  deal_id = deal['id']

  if deal_status != 'signed'
    return {
      'message': 'Deal not signed yet, nothing to do for %s' % deal_id
    }.to_json
  end

  # Create account, products, plans, and subscription
  message = complete_signed_workflow(deal)

  return {
    'message': message
  }.to_json
end

def complete_signed_workflow(deal)
  @zuora_client = zuora_init
  pp deal['customer']
  # When deal.customer comes through, we can create or update accounts.
  account = zuora_create_account(@zuora_client, deal, "USD")

  if account == false
    return "Unable to complete signed workflow operation."
  end

  skus = deal['skus']
  if skus.length > 0
    pp "Automatically building SKUS..."
    skus.map { |sku|
      product = zuora_create_product(@zuora_client, sku['id'], sku['friendly_name'], sku['description'])

      # Create ProductRatePlan
      plan = zuora_create_plan(@zuora_client,
        product,
        sku,
      )

      # Create UnitOfMeasure object
      plan_uom = zuora_create_uom(@zuora_client,
        sku
      )

      # Create ProductRatePlanCharge - This is where pricing is set by default.
      plan_charge = zuora_create_plan_charge(@zuora_client,
        product,
        sku,
        plan,
      )

      # TODO: Create Subscription for Customer
      pp plan_charge
    }
    pp "%s updated." % skus.length
  end

  return 'Created Zuora Plan for %s' % deal['id']
end
