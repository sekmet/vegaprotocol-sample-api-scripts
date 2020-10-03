#!/usr/bin/env bash

# Script language: bash

# Talks to:
# - Vega wallet (REST)
# - Vega node (REST)
#
# Apps/Libraries:
# - REST: curl

# Note: this file uses smart-tags in comments to section parts of the code to
# show them as snippets in our documentation. They are not necessary to be
# included when creating your own custom code.
#
# Example of smart-tags:
#  __something:
# some code here
# :something__
#

source helpers.sh

check_url "NODE_URL_REST" || exit 1
check_url "WALLETSERVER_URL" || exit 1

check_var "WALLET_NAME" || exit 1
check_var "WALLET_PASSPHRASE" || exit 1

echo "Logging into wallet: $WALLET_NAME"

# __login_wallet:
# Log in to an existing wallet
req='{"wallet": "'"$WALLET_NAME"'","passphrase": "'"$WALLET_PASSPHRASE"'"}'
url="$WALLETSERVER_URL/api/v1/auth/token"
response="$(curl -s -XPOST -d "$req" "$url")"
token="$(echo "$response" | jq -r .token)"
# :login_wallet__

test "$token" == null && exit 1
echo "Logged in to wallet successfully"

# __get_pubkey:
# List key pairs and select public key to use
hdr="Authorization: Bearer $token"
url="$WALLETSERVER_URL/api/v1/keys"
response="$(curl -s -XGET -H "$hdr" "$url")"
pubKey="$(echo "$response" | jq -r '.keys[0].pub')"
# :get_pubkey__

test -n "$pubKey" || exit 1
test "$pubKey" == null && exit 1
echo "Selected pubkey for signing"

# __get_market:
# Request the identifier for the market to place on
url="$NODE_URL_REST/markets"
response="$(curl -s "$url")"
marketID="$(echo "$response" | jq -r '.markets[0].id')"
# :get_market__

echo "Market found: $marketID"

# __get_expiry_time:
# Request the current blockchain time, calculate an expiry time
url="$NODE_URL_REST/time"
response="$(curl -s "$url")"
blockchaintime="$(echo "$response" | jq -r .timestamp)"
expiresAt="$((blockchaintime+120*10**9))" # expire in 2 minutes
# :get_expiry_time__

echo "Blockchain time: $expiresAt"

# __prepare_submit_order:
# Prepare a submit order message
# Note: price is an integer. For example 123456 is a price of 1.23456,
# assuming 5 decimal places.
cat >req.json <<EOF
{
    "submission": {
        "marketID": "$marketID",
        "partyID": "$pubKey",
        "price": "1",
        "size": "10",
        "side": "SIDE_BUY",
        "timeInForce": "TIF_GTT",
        "expiresAt": "$expiresAt",
        "type": "TYPE_LIMIT"
    }
}
EOF
url="$NODE_URL_REST/orders/prepare/submit"
response="$(curl -s -XPOST -d @req.json "$url")"
orderRef="$(echo "$response" | jq -r '.submitID')"
# :prepare_submit_order__

echo "Prepared order, ref: $orderRef"

# __sign_tx_order:
# Sign the prepared transaction
# Note: Setting propagate to true will also submit to a Vega node
blob="$(echo "$response" | jq -r .blob)"
test "$blob" == null && exit 1
cat >req.json <<EOF
{
    "tx": "$blob",
    "pubKey": "$pubKey",
    "propagate": true
}
EOF
url="$WALLETSERVER_URL/api/v1/messages"
response="$(curl -s -XPOST -H "$hdr" -d @req.json "$url")"
# :sign_tx_order__

signedTx="$(echo "$response" | jq .signedTx)"
test "$signedTx" == null && exit 1

echo "Signed order and sent to Vega"

# Wait for order submission to be included in a block
echo "Waiting for blockchain..."
sleep 2.5s
url="$NODE_URL_REST/orders/$orderRef"
response="$(curl -s "$url")"
orderID="$(echo "$response" | jq -r '.order.id')"
orderStatus="$(echo "$response" | jq -r '.order.status')"

echo "Order processed, ID: $orderID, Status: $orderStatus"

# -----------------------------
# TODO: Order amendment >= 0.25
# -----------------------------

# __prepare_cancel_order:
# Prepare a cancel order message
cat >req.json <<EOF
{
    "cancellation": {
        "partyID": "$pubKey",
        "marketID": "$marketID",
        "orderID": "$orderID"
    }
}
EOF
url="$NODE_URL_REST/orders/prepare/cancel"
response="$(curl -s -XPOST -d @req.json "$url")"
# :prepare_cancel_order__

echo "Cancellation prepared for order ID: $orderID"

# __sign_tx_cancel:
# Sign the prepared transaction for cancellation
# Note: Setting propagate to true will also submit to a Vega node
blob="$(echo "$response" | jq -r .blob)"
test "$blob" == null && exit 1
cat >req.json <<EOF
{
    "tx": "$blob",
    "pubKey": "$pubKey",
    "propagate": true
}
EOF
url="$WALLETSERVER_URL/api/v1/messages"
response="$(curl -s -XPOST -H "$hdr" -d @req.json "$url")"
# :sign_tx_cancel__

signedTx="$(echo "$response" | jq .signedTx)"
test "$signedTx" == null && exit 1

echo "Signed cancellation and sent to Vega"

# Wait for order submission to be included in a block
echo "Waiting for blockchain..."
sleep 2.5s
url="$NODE_URL_REST/orders/$orderRef"
response="$(curl -s "$url")"
orderID="$(echo "$response" | jq -r '.order.id')"
orderStatus="$(echo "$response" | jq -r '.order.status')"

test "$orderStatus" != "STATUS_CANCELLED" && exit 1

# Completed.
echo "Cancelled order successfully:"
echo "ID: $orderID, Status: $orderStatus"