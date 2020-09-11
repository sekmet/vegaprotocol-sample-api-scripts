#!/usr/bin/python3

# Note: this file uses smart-tags within comments to section parts
# of the code to show as snippets in our documentation. They are not
# necessary to include when creating your own custom code.
# Examples of smart-tags:  __vega_wallet:  and  :vega_wallet__

import base64
import os

from google.protobuf.empty_pb2 import Empty

# __import_client:
import vegaapiclient as vac

# :import_client__

import helpers


node_url_grpc = os.getenv("NODE_URL_GRPC")
if not helpers.check_var(node_url_grpc):
    print("Error: Invalid NODE_URL_GRPC.")
    exit(1)

walletserver_url = os.getenv("WALLETSERVER_URL")
if not helpers.check_url(walletserver_url):
    print("Error: Invalid WALLETSERVER_URL.")
    exit(1)

wallet_name = os.getenv("WALLET_NAME")
if not helpers.check_var(wallet_name):
    print("Error: Invalid WALLET_NAME.")
    exit(1)

wallet_passphrase = os.getenv("WALLET_PASSPHRASE")
if not helpers.check_var(wallet_passphrase):
    print("Error: Invalid WALLET_PASSPHRASE.")
    exit(1)

# __create_wallet:
# Vega node: Create client for accessing public data
datacli = vac.VegaTradingDataClient(node_url_grpc)

# Vega node: Create client for trading (e.g. submitting orders)
tradingcli = vac.VegaTradingClient(node_url_grpc)

# Wallet server: Create a walletclient (see above for details)
walletclient = vac.WalletClient(walletserver_url)
walletclient.login(wallet_name, wallet_passphrase)
# :create_wallet__

# __get_market:
# Get a list of markets
markets = datacli.Markets(Empty()).markets
marketID = markets[0].id
# :get_market__

# __generate_keypair:
GENERATE_NEW_KEYPAIR = False
if GENERATE_NEW_KEYPAIR:
    # If you don't already have a keypair, generate one.
    response = walletclient.generatekey(wallet_passphrase, [])
    helpers.check_response(response)
    pubKey = response.json()["key"]["pub"]
else:
    # List keypairs
    response = walletclient.listkeys()
    helpers.check_response(response)
    keys = response.json()["keys"]
    assert len(keys) > 0
    pubKey = keys[0]["pub"]
# :generate_keypair__

# __prepare_order:
# Vega node: Prepare the SubmitOrder
order = vac.api.trading.SubmitOrderRequest(
    submission=vac.vega.OrderSubmission(
        marketID=marketID,
        partyID=pubKey,
        # price is an integer. For example 123456 is a price of 1.23456,
        # assuming 5 decimal places.
        price=100000,
        side=vac.vega.Side.SIDE_BUY,
        size=1,
        timeInForce=vac.vega.Order.TimeInForce.TIF_GTC,
        type=vac.vega.Order.Type.TYPE_LIMIT,
    )
)
print(f"Request for PrepareSubmitOrder: {order}")
response = tradingcli.PrepareSubmitOrder(order)
print(f"Response from PrepareSubmitOrder: {response}")
# :prepare_order__

# __sign_tx:
# Wallet server: Sign the prepared transaction
blob_base64 = base64.b64encode(response.blob).decode("ascii")
print(f"Request for SignTx: blob={blob_base64}, pubKey={pubKey}")
response = walletclient.signtx(blob_base64, pubKey)
helpers.check_response(response)
responsejson = response.json()
print(f"Response from SignTx: {responsejson}")
signedTx = responsejson["signedTx"]
# :sign_tx__

# __submit_tx:
# Vega node: Submit the signed transaction
request = vac.api.trading.SubmitTransactionRequest(
    tx=vac.vega.SignedBundle(
        tx=base64.b64decode(signedTx["tx"]),
        sig=vac.vega.Signature(
            sig=base64.b64decode(signedTx["sig"]["sig"]),
            algo="vega/ed25519",
            version=1,
        ),
    ),
)
print(f"Request for SubmitTransaction: {request}")
response = tradingcli.SubmitTransaction(request)
# :submit_tx__
assert response.success
print("All is well.")
