// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title IERC20 — Minimal ERC20 interface
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title HiveFaucet — Daily token claim for hiveUSD
/// @notice Users can claim 1000 hiveUSD every 24 hours
contract HiveFaucet {
    IERC20 public immutable token;
    address public owner;

    uint256 public constant CLAIM_AMOUNT = 25000 * 1e18;     // 25000 hiveUSD
    uint256 public constant COOLDOWN = 24 hours;

    mapping(address => uint256) public lastClaim;

    event Claimed(address indexed user, uint256 amount, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
    }

    /// @notice Claim 1000 hiveUSD (once per 24h)
    function claim() external {
        require(block.timestamp >= lastClaim[msg.sender] + COOLDOWN, "cooldown");
        lastClaim[msg.sender] = block.timestamp;
        require(token.transfer(msg.sender, CLAIM_AMOUNT), "transfer failed");
        emit Claimed(msg.sender, CLAIM_AMOUNT, block.timestamp);
    }

    /// @notice Check if user can claim
    function canClaim(address user) external view returns (bool) {
        return block.timestamp >= lastClaim[user] + COOLDOWN;
    }

    /// @notice Time until next claim (0 if can claim now)
    function timeUntilClaim(address user) external view returns (uint256) {
        uint256 next = lastClaim[user] + COOLDOWN;
        if (block.timestamp >= next) return 0;
        return next - block.timestamp;
    }

    /// @notice Withdraw tokens (owner only)
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(token.transfer(to, amount), "withdraw failed");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
