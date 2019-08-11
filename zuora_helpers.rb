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

require 'json'

# zuora_init - Creates a zuora api connection
def zuora_init()
  # Parameters -
  ZuoraAPI::Oauth.new(
    oauth_client_id: ENV['ZUORA_LOGIN'],
    oauth_secret: ENV['ZUORA_PASSWORD'],
    url: ENV['ZUORA_ENV'] != "production"?
      'https://rest.apisandbox.zuora.com'
      : 'https://rest.zuora.com',
  )
end


# zuora_request - Zuora Client wrapper method to send rest calls to Zuora.
def zuora_request(zuora_client, resource, request, method)
  url = zuora_client.rest_endpoint(resource)
  pp "[%s] - [%s] product %s" % [method, url, resource]
  response = false
  begin
    response = zuora_client.rest_call(
      method: method,
      body: request.to_json,
      headers: {
        'Content-Type': 'application/json',
      },
      url: url,
      debug: true,
    )
  rescue ZuoraAPI::Exceptions::ZuoraAPIError => e
    pp e
    raise e
  end

  return response
end

def zuora_get_products(zuora_client)
  response = zuora_client.rest_call(
    method: :get,
    body: {},
    url: zuora_client.rest_endpoint("catalog/products?sku=pageSize=100")
  )
  return response[0]['products']
end

def zuora_create_account(zuora_client, deal, currency)
  lead_contact = deal['lead_contact']
  customer = deal['customer']
  account_id = deal['account_id']
  billing_contact = deal['billing_contact']

  ## Uncomment for testing override of address
  billing_contact['address'] = '123 Test Street'
  billing_contact['city'] = 'San Francisco'
  billing_contact['country'] = 'USA'
  billing_contact['state'] = 'CA'
  billing_contact['postal_code'] = '94105'

  additionalEmailAddresses = []
  if lead_contact['email']
    additionalEmailAddresses << lead_contact['email']
  end
  billing_name = billing_contact['name'].split(' ')
  first_name = billing_name.length > 0? billing_name[0] : ''
  last_name = billing_name.length > 1? billing_name[-1] : ''

  account = {
    "accountNumber": account_id,
    "additionalEmailAddresses": additionalEmailAddresses,
    "autoPay": false,
    "billCycleDay": 0,
    "billToContact": {
      "address1": billing_contact['address'],
      "city": billing_contact['city'],
      "country": billing_contact['country'],
      "firstName": first_name,
      "lastName": last_name,
      "state": billing_contact['state'],
      "workEmail": billing_contact['email'],
      "zipCode": billing_contact['postal_code']
    },
    "currency": currency,
    "name": customer['legal_name'],
    "notes": "Created by RevOps.",
  }
  pp account
  response = zuora_request(zuora_client, "accounts", account, :post)
  pp response
  if response == false
    pp "Unable to create account: %s" % response
    return false
  else
    return response
  end
end

# zuora_create_product - Idempotently creates new products in Zuora
def zuora_create_product(zuora_client, id, name, description)
  product = false

  # If SKU already exists by sku.id, skip creating the product in Zuora.
  pp "Checking for product %s" % id

  # Find existing product by SKU by fetching the catalog.
  # This can probably use some optimization in the future.
  products = zuora_get_products(zuora_client)
  products.each { |_product|
    if _product['sku'] == id
      product = _product
    end
  }

  if product == false
    pp "Product not found"
    product = zuora_request(zuora_client, "object/product",
      {
        "Description": description,
        "Name": name,
        "EffectiveEndDate": "2066-10-20",
        "EffectiveStartDate": "1966-10-20",
        "SKU": id,
      },
      :post
    )
  else
    pp "Existing product found: %s" % product
    response = zuora_request(zuora_client, "object/product/%s" % product['id'],
      {
        "Description": description,
        "Name": name,
        "EffectiveEndDate": "2066-10-20",
        "EffectiveStartDate": "1966-10-20",
        "SKU": id,
      },
      :put
    )
    if response.length == 1
      product = response[0]
    end
  end

  return product
end

# zuora_create_plan - Idempotently creates new plans in Zuora
def zuora_create_plan(zuora_client, product, sku)
  plan = false

  if product == false
    pp "Can't create plan, product not found"
    return plan
  end

  amount = sku['monthly_price']
  schedule = get_interval_schedule(sku['billing_schedule'])
  name = "#{product['id']}-#{schedule}-#{amount}"

  # If SKU already exists by sku.id, skip creating the product in Zuora.
  pp "Checking for plan #{name}"

  # Find existing plan by id on the selected product.
  product['productRatePlans'].each { |_plan|
    pp _plan
    if _plan['name'] == name
      plan = _plan
    end
  }

  if plan == false
    response = zuora_request(zuora_client, "object/product-rate-plan",
      {
        "Name": name,
        "EffectiveEndDate": "2066-10-20",
        "EffectiveStartDate": "1966-10-20",
        "ProductId": product['id'],
      },
      :post
    )
    if response.length > 0
      plan = response[0]
    end
  else
    pp "Plan already exists"
  end

  return plan
end

def zuora_create_plan_charge(zuora_client, product, sku, plan)
  charge = false

  schedule = get_interval_schedule(sku['billing_schedule'])

  if schedule == 'annual'
    amount = sku['annual_price']
    currency = sku['annual_price_currency']
  else
    amount = sku['monthly_price']
    currency = sku['monthly_price_currency']
  end

  name = "#{product['id']}-#{schedule}-#{amount}"

  plan['productRatePlanCharges'].each { |_charge|
    pp _charge
    if _charge['name'] == name
      charge = _charge
    end
  }

  # TODO: Handle permutations of SKU and create mapping
  charge_model = "Per Unit Pricing"
  charge_type = "Recurring"
  billing_period_alignment = "AlignToTermStart"

  if charge == false
    charge_request = {
      "AccountingCode": "Deferred Revenue",
      "BillCycleType": "DefaultFromCustomer",
      "BillingPeriod": schedule == 'annual'? "Annual" : "Month",
      "ChargeModel": charge_model,
      "ChargeType": charge_type,
      "DefaultQuantity": sku['quantity'],
      "DeferredRevenueAccount": "Deferred Revenue",
      "Name": name,
      "ProductRatePlanChargeTierData": {
        "ProductRatePlanChargeTier": [
          {
            "Active": true,
            "Currency": currency,
            "Price": amount
          }
        ]
      },
      "ProductRatePlanId": plan['id'],
      "RecognizedRevenueAccount": "Accounts Receivable",
      "TriggerEvent": "ContractEffective",
      "UOM": sku['unit_name'] != nil ? sku['unit_name'][0..24] : 'unit',
      "UseDiscountSpecificAccountingCode": false
    }
    pp charge_request

    response = zuora_request(
      zuora_client,
      "object/product-rate-plan-charge",
      charge_request,
      :post
    )

    if response.length > 0
      charge = response[0]
    end
  else
    pp "Charge already exists"
  end

  return charge
end

def zuora_create_uom(zuora_client, sku)
  uom = false
  begin
    response = zuora_request(
      zuora_client,
      'object/unit-of-measure',
      {
        "Active": true,
        "DecimalPlaces": 9,
        "DisplayedAs": sku['unit_name'][0..24],
        "RoundingMode": "UP",
        "UomName": sku['unit_name'][0..24]
      },
      :post
    )
  rescue ZuoraAPI::Exceptions::ZuoraAPIError => e
    if e.code != 400
      raise e
    end
  end

  return uom
end

def get_interval_schedule(billing_schedule)
  if billing_schedule == 'usage'
    return 'month'
  else
    return billing_schedule
  end
end
