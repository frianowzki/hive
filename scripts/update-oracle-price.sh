#!/bin/bash
# Silent oracle price updater for hiveUSD (USDT 1:1)
# Fetches USDT price from CoinGecko and updates HiveOracle on-chain

ORACLE_ADDR="0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE"
HIVEUSD_ADDR="0x60601e48038E32dBCd9A9667c589bf6D39A32fb5"
RPC_URL="https://rpc.ritualfoundation.org"
PRIVATE_KEY=$(grep PRIVATE_KEY /home/frio/hive/.env | cut -d= -f2)

# Fetch USDT price from CoinGecko
PRICE_JSON=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=tether&vs_currencies=usd&precision=8" 2>/dev/null)
USDT_PRICE=$(echo "$PRICE_JSON" | jq -r '.tether.usd // empty' 2>/dev/null)

if [ -z "$USDT_PRICE" ]; then
    # Fallback to $1.00 if API fails
    USDT_PRICE="1.00000000"
fi

# Convert to 8 decimals (multiply by 1e8)
PRICE_INT=$(echo "$USDT_PRICE" | awk '{printf "%.0f", $1 * 100000000}')

# Update oracle
~/.foundry/bin/cast send $ORACLE_ADDR "updatePrice(address,uint256,string)" $HIVEUSD_ADDR $PRICE_INT "coingecko" --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1

echo "$(date): Updated hiveUSD price to $USDT_PRICE ($PRICE_INT)" >> /home/frio/hive/logs/oracle-updates.log 2>/dev/null
