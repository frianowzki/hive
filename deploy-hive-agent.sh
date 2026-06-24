#!/bin/bash
# Deploy HiveSovereignAgentRitual to Ritual Chain
# Usage: ./deploy-hive-agent.sh [PRIVATE_KEY] [BUDGET]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Contract addresses from hive-contracts.js
REGISTRY="0x89Cff106458261b48597ee0307017504080182eE"
STAKING="0x8D2A42Fe7845F165264d042267a3bD8EBae83d28"
LAUNCHPAD="0x8eb73b9e2dD62EcFC9C61861638C45afe003d95b"
GOVERNANCE="0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702"
TREASURY="0x90fbd495c888ae010e40FD299E143FabFcf08C18"
PORTFOLIO="0x81E38ad29B869De5dd99bC5da1386b65Ef2Da066"
MARKETMAKER="0x62C8AB145AA677792b7E7d1f0Bf64000D3DC637D"

# Scheduler precompile (Ritual Chain)
SCHEDULER="0x0000000000000000000000000000000000000808"

# Check for private key
if [ -z "$1" ]; then
  echo -e "${RED}Error: Private key required${NC}"
  echo "Usage: ./deploy-hive-agent.sh <PRIVATE_KEY> [BUDGET]"
  echo "   or: ./deploy-hive-agent.sh 0x... 0.5"
  exit 1
fi

PRIVATE_KEY="$1"
BUDGET="${2:-0.5}" # Default 0.5 RITUAL

# Validate budget
if (( $(echo "$BUDGET > 0.5" | bc -l) )); then
  echo -e "${RED}Error: Budget cannot exceed 0.5 RITUAL${NC}"
  exit 1
fi

echo -e "${GREEN}🐝 Deploying HiveSovereignAgentRitual to Ritual Chain${NC}"
echo ""
echo "Constructor args:"
echo "  Scheduler:     $SCHEDULER"
echo "  Registry:      $REGISTRY"
echo "  HiveStaking:   $STAKING"
echo "  HiveLaunchPad: $LAUNCHPAD"
echo "  HiveGovernance: $GOVERNANCE"
echo "  HiveTreasury:  $TREASURY"
echo "  HivePortfolio: $PORTFOLIO"
echo "  HiveMarketMaker: $MARKETMAKER"
echo "  Budget:        $BUDGET RITUAL"
echo ""

# Check if forge is installed
if ! command -v forge &> /dev/null; then
  echo -e "${RED}Error: forge not found. Install Foundry first.${NC}"
  echo "Run: curl -L https://foundry.paradigm.xyz | bash"
  exit 1
fi

# Build the contract
echo -e "${YELLOW}Building contract...${NC}"
cd "$(dirname "$0")"
forge build --contracts src/agent/HiveSovereignAgentRitual.sol

# Deploy
echo -e "${YELLOW}Deploying...${NC}"
forge create src/agent/HiveSovereignAgentRitual.sol:HiveSovereignAgent \
  --constructor-args \
    "$SCHEDULER" \
    "$REGISTRY" \
    "$STAKING" \
    "$LAUNCHPAD" \
    "$GOVERNANCE" \
    "$TREASURY" \
    "$PORTFOLIO" \
    "$MARKETMAKER" \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key "$PRIVATE_KEY" \
  --value "${BUDGET}ether"

echo ""
echo -e "${GREEN}✅ Agent deployed!${NC}"
echo ""
echo "Next steps:"
echo "1. Start the agent: call start(200) on the deployed contract"
echo "2. Fund the agent with RITUAL for gas (max 0.5 RITUAL)"
echo "3. Monitor on: https://explorer.ritualfoundation.org/agents"
