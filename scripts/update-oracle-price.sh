#!/bin/bash
# Hive Oracle Price Updater
# Calls updatePrice(address,uint256,string) on HiveOracle contract on Ritual Testnet
# Uses owner private key from .env

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/oracle-update.log"

# Contract & RPC
ORACLE_CONTRACT="0x439F5DB6C09a4a307dE4bE51BABA557947d60F39"
ETH_TOKEN="0x60601e48038E32dBCd9A9667c589bf6D39A32fb5"
RPC_URL="https://rpc.ritualfoundation.org"
CAST="/home/frio/.foundry/bin/cast"

# Load env
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "ERROR: .env not found at $ENV_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# Ensure log dir exists
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$TIMESTAMP] Starting oracle price update..." | tee -a "$LOG_FILE"

# Fetch ETH price from CoinGecko
ETH_PRICE_JSON=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd" 2>/dev/null)
ETH_PRICE=$(echo "$ETH_PRICE_JSON" | grep -o '"usd":[0-9.]*' | cut -d: -f2)

if [ -z "$ETH_PRICE" ]; then
    echo "[$TIMESTAMP] ❌ Could not fetch ETH price from CoinGecko" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[$TIMESTAMP] CoinGecko ETH price: \$${ETH_PRICE}" | tee -a "$LOG_FILE"

# Convert to uint256 with 8 decimal precision (e.g., 1819.80 -> 181980000000)
PRICE_SCALED=$(echo "$ETH_PRICE * 100000000" | bc | cut -d. -f1)

echo "[$TIMESTAMP] Scaled price: ${PRICE_SCALED}" | tee -a "$LOG_FILE"

# Call updatePrice(address,uint256,string) on oracle contract
RESULT=$($CAST send "$ORACLE_CONTRACT" \
    "updatePrice(address,uint256,string)" \
    "$ETH_TOKEN" \
    "$PRICE_SCALED" \
    "coingecko" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --gas-limit 200000 2>&1)

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    STATUS=$(echo "$RESULT" | grep "status" | head -1 | awk '{print $2}')
    TX_HASH=$(echo "$RESULT" | grep "^transactionHash" | awk '{print $2}')
    GAS_USED=$(echo "$RESULT" | grep "gasUsed" | awk '{print $2}')

    if [ "$STATUS" = "1" ]; then
        echo "[$TIMESTAMP] ✅ Oracle price updated: \$${ETH_PRICE} (${PRICE_SCALED})" | tee -a "$LOG_FILE"
        echo "  TX: $TX_HASH" | tee -a "$LOG_FILE"
        echo "  Gas: $GAS_USED" | tee -a "$LOG_FILE"
    else
        echo "[$TIMESTAMP] ❌ Oracle price update REVERTED (status 0)" | tee -a "$LOG_FILE"
        echo "  TX: $TX_HASH" | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "[$TIMESTAMP] ❌ Oracle price update FAILED" | tee -a "$LOG_FILE"
    echo "  Error: $RESULT" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[$TIMESTAMP] Done." | tee -a "$LOG_FILE"
