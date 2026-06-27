#!/bin/bash
# Withdraw 0.49 RITUAL from HiveSovereignAgentRitual RitualWallet after lock expires
# Lock expires at block 37196853

set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.ritualfoundation.org"
PRIVATE_KEY=$(grep '^PRIVATE_KEY=' /home/frio/hive/.env | cut -d= -f2-)
AGENT="0xfbdb2b5116e421e33b32a75a1ca82e234396c271"
USER="0x63C5341454F66a32553CE598e06861E11095d39C"
LOCK_UNTIL=37196853

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
echo "Current block: $CURRENT_BLOCK"
echo "Lock until:    $LOCK_UNTIL"

if [ "$CURRENT_BLOCK" -lt "$LOCK_UNTIL" ]; then
    REMAINING=$((LOCK_UNTIL - CURRENT_BLOCK))
    echo "Lock still active. $REMAINING blocks remaining (~$((REMAINING * 350 / 1000 / 60)) minutes)"
    exit 0
fi

echo "Lock expired! Withdrawing 0.49 RITUAL..."

# Withdraw from RitualWallet
cast send "$AGENT" "withdrawFromWallet(uint256)" 490000000000000000 \
    --rpc-url "$RPC" \
    --private-key "$PRIVATE_KEY" \
    --gas-limit 100000

echo ""
echo "Withdrawal complete!"
echo "User wallet balance: $(cast balance "$USER" --rpc-url "$RPC" --ether) RITUAL"
