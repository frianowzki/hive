// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title HiveToken — Token standard for Hive launchpad
/// @notice ERC20 with built-in vesting, transfer restrictions, and metadata
/// @dev Launched via HiveClearing auction, integrated with HiveID

contract HiveToken {
    // ═══ ERC20 State ═══

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1B tokens

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ═══ Vesting State ═══

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 releaseInterval;
        bool cancelled;
    }

    // beneficiary => schedule
    mapping(address => VestingSchedule) public vestingSchedules;
    mapping(address => bool) public hasVesting;

    // ═══ Transfer Restrictions ═══

    enum TransferMode {
        OPEN,               // Anyone can transfer
        WHITELIST_ONLY,     // Only whitelisted addresses
        LAUNCHPAD_ONLY      // Only during/after launchpad sale
    }

    TransferMode public transferMode;
    mapping(address => bool) public whitelist;

    // ═══ Metadata ═══

    string public tokenURI;     // Link to full metadata
    address public project;     // Project HiveID primary wallet
    bytes32 public projectIdHash; // Project HiveID hash
    uint256 public createdAt;
    bool public revoked;        // Can be revoked by admin

    // ═══ Roles ═══

    address public owner;

    uint256 public constant ADMIN_DELAY = 24 hours;
    mapping(bytes32 => uint256) public pendingActions;
    address public pendingOwner;
    address public minter;      // HiveLaunchPad contract

    // ═══ Events ═══

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event VestingCreated(address indexed beneficiary, uint256 amount);
    event VestingReleased(address indexed beneficiary, uint256 amount);
    event VestingCancelled(address indexed beneficiary);
    event TransferModeChanged(TransferMode newMode);
    event WhitelistUpdated(address indexed account, bool status);
    event TokenRevoked();

    // ═══ Errors ═══

    error TransferRestricted();
    error InsufficientBalance();
    error InsufficientAllowance();
    error MaxSupplyExceeded();
    error NoVestingSchedule();
    error VestingNotStarted();
    error NothingToRelease();
    error NotMinter();
    error NotOwner();
    error TokenIsRevoked();

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    modifier notRevoked() {
        if (revoked) revert TokenIsRevoked();
        _;
    }

    // ═══ Constructor ═══

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _project,
        bytes32 _projectIdHash,
        string memory _tokenURI
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        project = _project;
        projectIdHash = _projectIdHash;
        tokenURI = _tokenURI;
        owner = _project;
        minter = _project; // Initially, project is minter
        createdAt = block.timestamp;
        transferMode = TransferMode.LAUNCHPAD_ONLY; // Restricted until launch completes
    }

    // ═══ ERC20 Functions ═══

    function transfer(address to, uint256 amount) external notRevoked returns (bool) {
        if (!_canTransfer(msg.sender, to)) revert TransferRestricted();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external notRevoked returns (bool) {
        if (!_canTransfer(from, to)) revert TransferRestricted();
        if (balanceOf[from] < amount) revert InsufficientBalance();
        if (allowance[from][msg.sender] < amount) revert InsufficientAllowance();

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }

    // ═══ Minting (Launchpad) ═══

    /// @notice Mint tokens (only minter/launchpad)
    function mint(address to, uint256 amount) external onlyMinter notRevoked {
        if (totalSupply + amount > MAX_SUPPLY) revert MaxSupplyExceeded();

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @notice Set minter (transfer minting rights to launchpad contract)
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    // ═══ Vesting ═══

    /// @notice Create vesting schedule for a beneficiary
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 releaseInterval
    ) external onlyOwner {
        require(!hasVesting[beneficiary], "HiveToken: already has vesting");

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            releasedAmount: 0,
            startTime: block.timestamp,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            releaseInterval: releaseInterval,
            cancelled: false
        });

        hasVesting[beneficiary] = true;

        // Transfer tokens to contract for vesting
        balanceOf[address(this)] += amount;
        balanceOf[owner] -= amount;

        emit VestingCreated(beneficiary, amount);
    }

    /// @notice Release vested tokens
    function releaseVesting() external notRevoked {
        VestingSchedule storage schedule = _getVesting(msg.sender);
        if (schedule.totalAmount == 0) revert NoVestingSchedule();
        if (schedule.cancelled) revert NoVestingSchedule();

        uint256 claimable = _claimableAmount(schedule);
        if (claimable == 0) revert NothingToRelease();

        schedule.releasedAmount += claimable;

        balanceOf[address(this)] -= claimable;
        balanceOf[msg.sender] += claimable;

        emit VestingReleased(msg.sender, claimable);
    }

    /// @notice Get claimable amount
    function claimableVesting(address beneficiary) external view returns (uint256) {
        VestingSchedule storage schedule = _getVesting(beneficiary);
        if (schedule.totalAmount == 0 || schedule.cancelled) return 0;
        return _claimableAmount(schedule);
    }

    function _claimableAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) return 0;

        uint256 elapsed = block.timestamp - schedule.startTime;
        uint256 vestedAmount = (schedule.totalAmount * elapsed) / schedule.vestingDuration;
        if (vestedAmount > schedule.totalAmount) vestedAmount = schedule.totalAmount;

        return vestedAmount - schedule.releasedAmount;
    }


    function _getVesting(address beneficiary) internal view returns (VestingSchedule storage) {
        return vestingSchedules[beneficiary];
    }

    // ═══ Transfer Restrictions ═══

    function _canTransfer(address from, address to) internal view returns (bool) {
        if (transferMode == TransferMode.OPEN) return true;
        if (transferMode == TransferMode.WHITELIST_ONLY) {
            return whitelist[from] && whitelist[to];
        }
        // LAUNCHPAD_ONLY: only project can transfer until mode changes
        return from == owner || from == minter || whitelist[from];
    }

    function setTransferMode(TransferMode _mode) external onlyOwner {
        transferMode = _mode;
        emit TransferModeChanged(_mode);
    }

    function setWhitelist(address account, bool status) external onlyOwner {
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    // ═══ Admin ═══

    function revoke() external onlyOwner {
        revoked = true;
        emit TokenRevoked();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function scheduleAdminAction(address target, bytes calldata data) external onlyOwner {
        bytes32 actionHash = keccak256(abi.encode(target, data));
        pendingActions[actionHash] = block.timestamp + ADMIN_DELAY;
    }

    function executeAdminAction(address target, bytes calldata data) external onlyOwner {
        bytes32 actionHash = keccak256(abi.encode(target, data));
        require(pendingActions[actionHash] != 0, "not scheduled");
        require(block.timestamp >= pendingActions[actionHash], "timelock not expired");
        delete pendingActions[actionHash];
        (bool success, ) = target.call(data);
        require(success, "action failed");
    }

    // ═══ View ═══

    function getVestingSchedule(address beneficiary) external view returns (VestingSchedule memory) {
        return vestingSchedules[beneficiary];
    }

    // ═══ Receive ═══

    receive() external payable {}
}
