// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HiveAgentToken.sol";
import "./HiveBondingCurve.sol";

/// @title HiveTokenLaunchFactory - Pump.fun style token launcher
/// @notice Deploy tokens with bonding curves — no AI agents, no sovereign agents
/// @dev Separate from HiveFactory to keep agent and token flows independent
contract HiveTokenLaunchFactory {
    address public owner;
    address public platformTreasury;
    address public dexRouter;

    uint256 public constant TOKEN_LAUNCH_FEE = 0.01 ether;
    uint256 public virtualRitual = 1 ether;
    uint256 public virtualToken = 1_000_000_000 * 1e18;

    struct TokenLaunch {
        address token;
        address bondingCurve;
        address creator;
        string name;
        string symbol;
        string lore;
        uint256 createdAt;
    }

    mapping(uint256 => TokenLaunch) public tokenLaunches;
    uint256 public tokenLaunchCount;

    event TokenCreated(
        uint256 indexed tokenLaunchId,
        address indexed token,
        address indexed bondingCurve,
        string name,
        string symbol,
        address creator
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address platformTreasury_, address dexRouter_) {
        owner = msg.sender;
        platformTreasury = platformTreasury_;
        dexRouter = dexRouter_;
    }

    /// @notice Launch a token — name, symbol, description, graduation target
    /// @dev Fee: 0.01 RITUAL (msg.value). Token starts trading immediately on bonding curve.
    function createToken(
        string calldata name_,
        string calldata symbol_,
        string calldata lore_,
        uint256 graduationThreshold_
    ) external payable returns (uint256 tokenLaunchId) {
        require(msg.value >= TOKEN_LAUNCH_FEE, "insufficient launch fee");
        require(bytes(name_).length > 0, "empty name");
        require(bytes(symbol_).length > 0, "empty symbol");
        require(graduationThreshold_ >= 0.01 ether, "threshold too low");
        require(graduationThreshold_ <= 100 ether, "threshold too high");

        tokenLaunchId = tokenLaunchCount++;

        // 1. Deploy token with user-provided metadata
        HiveAgentToken token = new HiveAgentToken(name_, symbol_, lore_, address(this));

        // 2. Deploy bonding curve (platform gets all fees — no agent treasury)
        HiveBondingCurve curve = new HiveBondingCurve(
            address(token),
            address(this),
            platformTreasury,
            platformTreasury,
            dexRouter,
            virtualRitual,
            virtualToken,
            graduationThreshold_
        );

        // 3. Mint ALL tokens to bonding curve
        token.mint(address(curve), virtualToken);

        // 4. Set launch block + status
        token.setLaunchBlock(block.number);
        token.setTotalRaise(virtualRitual);
        token.setStatus(HiveAgentToken.AgentStatus.Launched);

        // 5. Store launch
        tokenLaunches[tokenLaunchId] = TokenLaunch({
            token: address(token),
            bondingCurve: address(curve),
            creator: msg.sender,
            name: name_,
            symbol: symbol_,
            lore: lore_,
            createdAt: block.number
        });

        // 6. Forward launch fee to treasury
        (bool sent,) = platformTreasury.call{value: msg.value}("");
        require(sent, "fee transfer failed");

        emit TokenCreated(tokenLaunchId, address(token), address(curve), name_, symbol_, msg.sender);
    }

    /// @notice Get all launched token addresses
    function getAllTokens() external view returns (address[] memory) {
        address[] memory tokens = new address[](tokenLaunchCount);
        for (uint256 i = 0; i < tokenLaunchCount; i++) {
            tokens[i] = tokenLaunches[i].token;
        }
        return tokens;
    }

    /// @notice Get token launch info by ID
    function getTokenLaunch(uint256 tokenLaunchId) external view returns (
        address token_,
        address bondingCurve_,
        address creator_,
        string memory name_,
        string memory symbol_,
        string memory lore_,
        uint256 createdAt_
    ) {
        TokenLaunch storage l = tokenLaunches[tokenLaunchId];
        return (l.token, l.bondingCurve, l.creator, l.name, l.symbol, l.lore, l.createdAt);
    }

    /// @notice Update virtual reserves (admin only)
    function setVirtualReserves(uint256 virtualRitual_, uint256 virtualToken_) external onlyOwner {
        virtualRitual = virtualRitual_;
        virtualToken = virtualToken_;
    }

    receive() external payable {}
}
