// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title HiveAgentToken - AI-Native ERC20 for Ritual Chain launchpad
/// @notice Each token is an autonomous AI agent with on-chain metadata
contract HiveAgentToken is ERC20, ERC20Burnable {
    enum AgentStatus { Draft, Minting, Launched, Active, Paused }

    address public factory;
    string internal _tokenName;
    string internal _tokenSymbol;
    string public lore;
    string public logoURI;
    AgentStatus public agentStatus;

    uint256 public launchBlock;
    uint256 public totalRaise;

    event LoreSet(string lore);
    event LogoSet(string logoURI);
    event StatusChanged(AgentStatus status);
    event Launched(uint256 block_);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory lore_,
        address factory_
    ) ERC20("", "") {
        _tokenName = name_;
        _tokenSymbol = symbol_;
        lore = lore_;
        factory = factory_;
        agentStatus = AgentStatus.Minting;
    }

    function name() public view override returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "not factory");
        _;
    }

    function setLore(string calldata lore_) external onlyFactory {
        lore = lore_;
        emit LoreSet(lore_);
    }

    function setName(string calldata name_) external onlyFactory {
        _tokenName = name_;
    }

    function setSymbol(string calldata symbol_) external onlyFactory {
        _tokenSymbol = symbol_;
    }

    function setLogoURI(string calldata logoURI_) external onlyFactory {
        logoURI = logoURI_;
        emit LogoSet(logoURI_);
    }

    function setStatus(AgentStatus status_) external onlyFactory {
        agentStatus = status_;
        emit StatusChanged(status_);
    }

    function mint(address to, uint256 amount) external onlyFactory {
        _mint(to, amount);
    }

    function setLaunchBlock(uint256 block_) external onlyFactory {
        launchBlock = block_;
        agentStatus = AgentStatus.Launched;
        emit Launched(block_);
    }

    function setTotalRaise(uint256 amount) external onlyFactory {
        totalRaise = amount;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC20).interfaceId;
    }
}
