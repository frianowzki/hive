// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal Uniswap V2-style Pair for Ritual Testnet graduation
/// @notice Simplified x*y=k AMM with ERC20 LP tokens + native ETH (address(0)) support
contract RitualV2Pair {
    address public factory;
    address public router;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // ERC20 LP token state
    string  public name = "Hive LP Token";
    string  public symbol = "HIVE-LP";
    uint8   public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    // FIX: allow both factory and router to call mint/swap/burn
    modifier onlyFactoryOrRouter() {
        require(msg.sender == factory || msg.sender == router, "NOT_AUTHORIZED");
        _;
    }

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1, address _router) external {
        require(msg.sender == factory, "NOT_FACTORY");
        token0 = _token0;
        token1 = _token1;
        router = _router;
    }

    // --- ERC20 LP Functions ---
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "INSUFFICIENT_ALLOWANCE");
            allowance[from][msg.sender] = currentAllowance - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[from] = balanceOf[from] - amount;
        balanceOf[to] = balanceOf[to] + amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply = totalSupply + amount;
        balanceOf[to] = balanceOf[to] + amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] = balanceOf[from] - amount;
        totalSupply = totalSupply - amount;
        emit Transfer(from, address(0), amount);
    }

    // --- Helpers for native ETH (address(0)) handling ---

    /// @dev Get balance of an asset — native ETH balance for address(0), ERC20 balance otherwise
    function _balanceOf(address asset) internal view returns (uint256) {
        if (asset == address(0)) {
            return address(this).balance;
        }
        return IERC20Pair(asset).balanceOf(address(this));
    }

    /// @dev Safe transfer — native ETH .call{value} for address(0), ERC20 transfer otherwise
    function _safeTransferAny(address asset, address to, uint256 value) internal {
        if (asset == address(0)) {
            (bool success,) = to.call{value: value}("");
            require(success, "ETH_TRANSFER_FAILED");
        } else {
            _safeTransfer(asset, to, value);
        }
    }

    /// @dev Get reserves in the correct order for a given token pair
    /// @return reserveIn Reserve of the input token
    /// @return reserveOut Reserve of the output token
    function _getReserves(address tokenIn, address tokenOut) internal view returns (uint112 reserveIn, uint112 reserveOut) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        reserveIn = tokenIn == token0 ? _reserve0 : _reserve1;
        reserveOut = tokenIn == token0 ? _reserve1 : _reserve0;
    }

    // --- AMM Functions ---
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        unchecked {
            if (blockTimestamp > blockTimestampLast) {
                uint32 timeElapsed = blockTimestamp - blockTimestampLast;
                blockTimestampLast = blockTimestamp;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external onlyFactoryOrRouter returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = _balanceOf(token0);
        uint256 balance1 = _balanceOf(token1);
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // permanently lock first LP
        } else {
            liquidity = min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }
        require(liquidity > 0, "NO_LIQUIDITY");
        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }

    function burn(address to) external onlyFactoryOrRouter returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = _balanceOf(token0);
        uint256 balance1 = _balanceOf(token1);
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "NO_LIQUIDITY");
        _burn(address(this), liquidity);
        _safeTransferAny(token0, to, amount0);
        _safeTransferAny(token1, to, amount1);
        balance0 = _balanceOf(token0);
        balance1 = _balanceOf(token1);
        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external onlyFactoryOrRouter {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            require(to != token0 && to != token1, "INVALID_TO");
            if (amount0Out > 0) _safeTransferAny(token0, to, amount0Out);
            if (amount1Out > 0) _safeTransferAny(token1, to, amount1Out);
            balance0 = _balanceOf(token0);
            balance1 = _balanceOf(token1);
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT_AMOUNT");
        {
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
            require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * 1000**2, "K");
        }

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // Force reserves to match balances
    function sync() external onlyFactoryOrRouter {
        _update(_balanceOf(token0), _balanceOf(token1));
    }

    // --- Helpers ---
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Pair.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    receive() external payable {}
}

interface IERC20Pair {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
