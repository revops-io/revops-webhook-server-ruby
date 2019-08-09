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

# zuora_request - Zuora Client wrapper method to send rest calls to Zuora.
def zuora_request(zuora_client, resource, request, method)
  pp "[%s] product %s" % [method, resource]

  begin
    zuora_client.rest_call(
      method: method,
      body: JSON.generate(request),
      headers: {},
      url: zuora_client.rest_endpoint(resource)
    )
  rescue ZuoraAPI::Exceptions::ZuoraAPIError => e
    pp e
    return false
  end
end

def zuora_create_account(zuora_client)
  zuora_request(zuora_client, "accounts", {
    "additionalEmailAddresses": [
      "contact1@example.com",
      "contact2@example.com"
    ],
    "autoPay": false,
    "billCycleDay": 0,
    "billToContact": {
      "address1": "1051 E Hillsdale Blvd",
      "city": "Foster City",
      "country": "United States",
      "firstName": "John",
      "lastName": "Smith",
      "state": "CA",
      "workEmail": "smith@example.com",
      "zipCode": "94404"
    },
    "currency": "USD",
    "name": "RevOps Test",
    "notes": "This account is for demo purposes.",
  }, :post)
end

# zuora_create_product - Idempotently creates new products in Zuora
def zuora_create_product(zuora_client, id, name, description)

  # If SKU already exists by sku.id, skip creating the product in Zuora.
  product = zuora_request(zuora_client, "object/product/%s" % id, {}, :get)
  if product != false
    return product
  end

  zuora_request(zuora_client, "object/product",
    {
      "Description": description,
      "Name": name,
      "EffectiveEndDate": "2066-10-20",
      "EffectiveStartDate": "1966-10-20",
      "SKU": id,
    },
    :post
  )
end
