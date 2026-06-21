// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title HiveUSD — USD-pegged stablecoin for Hive platform
/// @notice 100B max supply, faucet-enabled, sale participation token
contract HiveUSD {
    // ═══ ERC20 State ═══
    string public name = "hiveUSD";
    string public symbol = "hiveUSD";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 1e18; // 100B

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ═══ Access Control ═══
    address public minter;
    address public owner;

    // ═══ Events ═══
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    modifier onlyMinter() {
        require(msg.sender == minter, "not minter");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _minter) {
        minter = _minter;
        owner = msg.sender;
    }

    // ═══ ERC20 Functions ═══
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(to != address(0), "transfer to zero");
        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ═══ Mint (minter only) ═══
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "mint to zero");
        require(totalSupply + amount <= MAX_SUPPLY, "max supply exceeded");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // ═══ Admin ═══
    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "zero address");
        emit MinterUpdated(minter, _minter);
        minter = _minter;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
