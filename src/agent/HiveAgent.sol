// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveAgent — AI Agent Gateway
/// @notice On-chain AI chatbot powered by Ritual LLM precompile
/// @dev Users query market analysis, token info, strategy advice via LLM

contract HiveAgent is RitualPrecompileConsumer {
    // ═══ State ═══

    struct Query {
        address user;
        string prompt;
        string response;
        uint256 timestamp;
        uint256 gasUsed;
        bool resolved;
    }

    mapping(uint256 => Query) public queries;
    mapping(address => uint256[]) public userQueries;
    mapping(address => uint256) public queryCount;

    uint256 public totalQueries;
    address public owner;
    bool public paused;

    // Rate limiting
    mapping(address => uint256) public lastQueryBlock;
    uint256 public constant RATE_LIMIT_BLOCKS = 3; // Min blocks between queries

    // ═══ Events ═══

    event QuerySubmitted(uint256 indexed queryId, address indexed user, string prompt);
    event QueryResolved(uint256 indexed queryId, string response);
    event AgentPaused(bool paused);

    // ═══ Errors ═══

    error AgentIsPaused();
    error RateLimited();
    error EmptyPrompt();
    error QueryNotPending();

    // ═══ Modifiers ═══

    modifier whenNotPaused() {
        if (paused) revert AgentIsPaused();
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveAgent: not owner");
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Core — Query LLM ═══

    /// @notice Ask the AI agent a question
    /// @param prompt The question/prompt
    /// @return queryId The query ID for tracking
    function ask(string calldata prompt) external whenNotPaused returns (uint256 queryId) {
        if (bytes(prompt).length == 0) revert EmptyPrompt();
        if (block.number - lastQueryBlock[msg.sender] < RATE_LIMIT_BLOCKS) revert RateLimited();

        queryId = totalQueries++;

        queries[queryId] = Query({
            user: msg.sender,
            prompt: prompt,
            response: "",
            timestamp: block.timestamp,
            gasUsed: 0,
            resolved: false
        });

        userQueries[msg.sender].push(queryId);
        queryCount[msg.sender]++;
        lastQueryBlock[msg.sender] = block.number;

        emit QuerySubmitted(queryId, msg.sender, prompt);

        // Call Ritual LLM precompile
        bytes memory input = _encodeLlmCall(prompt);
        bytes memory output = _executePrecompile(LLM_PRECOMPILE, input);

        // Decode response
        string memory response = abi.decode(output, (string));

        queries[queryId].response = response;
        queries[queryId].resolved = true;

        emit QueryResolved(queryId, response);

        return queryId;
    }

    // ═══ Pre-built Prompts ═══

    /// @notice Analyze a token for the user
    /// @param tokenName Name or symbol of the token
    function analyzeToken(string calldata tokenName) external whenNotPaused returns (uint256) {
        string memory prompt = string(
            abi.encodePacked(
                "Analyze the token ",
                tokenName,
                " for a DeFi user. Provide: 1) Risk assessment (1-10), ",
                "2) Liquidity analysis, 3) Smart contract audit status, ",
                "4) Team background, 5) Recommendation (buy/hold/avoid). ",
                "Be concise and data-driven."
            )
        );
        return this.ask(prompt);
    }

    /// @notice Get market sentiment for a category
    /// @param category e.g., "DeFi", "NFT", "L2", "AI tokens"
    function marketSentiment(string calldata category) external whenNotPaused returns (uint256) {
        string memory prompt = string(
            abi.encodePacked(
                "Provide current market sentiment analysis for ",
                category,
                " sector. Include: 1) Overall sentiment (bullish/bearish/neutral), ",
                "2) Key trends, 3) Risk factors, 4) Opportunities. ",
                "Format as structured analysis."
            )
        );
        return this.ask(prompt);
    }

    /// @notice Analyze user's portfolio
    /// @param holdings JSON string of user's holdings
    function portfolioAnalysis(string calldata holdings) external whenNotPaused returns (uint256) {
        string memory prompt = string(
            abi.encodePacked(
                "Analyze this DeFi portfolio and provide recommendations: ",
                holdings,
                ". Include: 1) Diversification score, 2) Risk level, ",
                "3) Rebalancing suggestions, 4) Yield optimization opportunities."
            )
        );
        return this.ask(prompt);
    }

    /// @notice Explain a vesting schedule
    /// @param vestingInfo JSON string of vesting details
    function explainVesting(string calldata vestingInfo) external whenNotPaused returns (uint256) {
        string memory prompt = string(
            abi.encodePacked(
                "Explain this token vesting schedule in simple terms: ",
                vestingInfo,
                ". Include: 1) When tokens unlock, 2) Total claimable now, ",
                "3) Next unlock date, 4) Strategy advice (claim now vs wait)."
            )
        );
        return this.ask(prompt);
    }

    // ═══ View ═══

    /// @notice Get user's query history
    function getUserQueries(address user) external view returns (uint256[] memory) {
        return userQueries[user];
    }

    /// @notice Get total queries by user
    function getUserQueryCount(address user) external view returns (uint256) {
        return queryCount[user];
    }

    // ═══ Admin ═══

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit AgentPaused(_paused);
    }
}
