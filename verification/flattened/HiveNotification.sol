// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

// src/notification/HiveNotification.sol

/**
 * @title HiveNotification
 * @notice On-chain event notification system for Hive
 * @dev Structured events for off-chain indexing + webhook integration
 * @author Hive Team
 */

/// @notice Interface for HiveID
interface IHiveID {
    function getUsername(address wallet) external view returns (string memory);
    function getPrimaryWallet(string calldata username) external view returns (address);
    function isVerified(address wallet) external view returns (bool);
}

contract HiveNotification {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;
    IHiveID public hiveID;

    /// @notice Event types for subscriptions
    enum EventType {
        SALE_START,         // New token sale launched
        SALE_END,           // Token sale ended
        PRICE_ALERT,        // Price threshold crossed
        STRATEGY_EXEC,      // AI strategy executed
        GOVERNANCE_VOTE,    // New governance vote
        REPUTATION_CHANGE,  // Reputation tier changed
        STAKE_CHANGE,       // Staking event
        REFERRAL_BONUS,     // Referral bonus received
        TREASURY_DIST,      // Treasury distribution
        BRAIN_ACTION        // AI agent action
    }

    /// @notice Subscription info per user
    struct Subscription {
        bool active;
        uint256 eventMask; // Bitmask of subscribed events
        string webhookUrl; // Encrypted webhook URL
        uint256 subscribedAt;
    }

    /// @notice User subscriptions: address => Subscription
    mapping(address => Subscription) public subscriptions;

    /// @notice Price alert: user => threshold => config
    struct PriceAlert {
        bool active;
        uint256 threshold;
        bool above; // true = alert when above, false = alert when below
        string token;
    }

    /// @notice user => alertId => PriceAlert
    mapping(address => mapping(uint256 => PriceAlert)) public priceAlerts;
    mapping(address => uint256) public alertCounter;

    /// @notice Notification history: user => index => Notification
    struct Notification {
        EventType eventType;
        uint256 timestamp;
        string title;
        string message;
        bytes data;
        bool read;
    }

    mapping(address => Notification[]) public notifications;

    /// @notice Max notifications per user
    uint256 public constant MAX_NOTIFICATIONS = 100;

    /// @notice Total notifications sent
    uint256 public totalNotifications;

    /// @notice Registered contracts that can emit notifications
    mapping(address => bool) public authorizedEmitters;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event NotificationSent(
        address indexed user,
        EventType indexed eventType,
        uint256 timestamp,
        string title,
        string message,
        bytes data
    );

    /// @notice Batch notification event
    event BatchNotification(
        address[] users,
        EventType indexed eventType,
        uint256 timestamp,
        string title,
        string message,
        bytes data
    );

    /// @notice Subscription events
    event Subscribed(address indexed user, uint256 eventMask);
    event Unsubscribed(address indexed user);
    event PriceAlertSet(address indexed user, uint256 alertId, string token, uint256 threshold, bool above);
    event PriceAlertTriggered(address indexed user, uint256 alertId, string token, uint256 currentPrice);
    event PriceAlertCancelled(address indexed user, uint256 alertId);
    event NotificationRead(address indexed user, uint256 index);
    event AllNotificationsRead(address indexed user);
    event EmitterAuthorized(address indexed emitter);
    event EmitterRevoked(address indexed emitter);
    event WebhookUpdated(address indexed user, string webhookUrl);

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveNotification: not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedEmitters[msg.sender] || msg.sender == owner,
            "HiveNotification: not authorized"
        );
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor(address _hiveID) {
        owner = msg.sender;
        hiveID = IHiveID(_hiveID);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SUBSCRIPTION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    /// @notice Subscribe to event types
    /// @param eventMask Bitmask of EventType flags
    /// @param webhookUrl Encrypted webhook URL
    function subscribe(uint256 eventMask, string calldata webhookUrl) external {
        require(eventMask > 0, "HiveNotification: empty mask");

        subscriptions[msg.sender] = Subscription({
            active: true,
            eventMask: eventMask,
            webhookUrl: webhookUrl,
            subscribedAt: block.timestamp
        });

        emit Subscribed(msg.sender, eventMask);
    }

    /// @notice Update subscription
    function updateSubscription(uint256 eventMask) external {
        require(subscriptions[msg.sender].active, "HiveNotification: not subscribed");
        subscriptions[msg.sender].eventMask = eventMask;
        emit Subscribed(msg.sender, eventMask);
    }

    /// @notice Update webhook URL
    function updateWebhook(string calldata webhookUrl) external {
        require(subscriptions[msg.sender].active, "HiveNotification: not subscribed");
        subscriptions[msg.sender].webhookUrl = webhookUrl;
        emit WebhookUpdated(msg.sender, webhookUrl);
    }

    /// @notice Unsubscribe
    function unsubscribe() external {
        delete subscriptions[msg.sender];
        emit Unsubscribed(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      PRICE ALERTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Set price alert
    /// @param token Token symbol
    /// @param threshold Price threshold in USD (8 decimals)
    /// @param above Alert when price goes above (true) or below (false)
    function setPriceAlert(
        string calldata token,
        uint256 threshold,
        bool above
    ) external returns (uint256) {
        uint256 alertId = alertCounter[msg.sender]++;

        priceAlerts[msg.sender][alertId] = PriceAlert({
            active: true,
            threshold: threshold,
            above: above,
            token: token
        });

        emit PriceAlertSet(msg.sender, alertId, token, threshold, above);
        return alertId;
    }

    /// @notice Cancel price alert
    function cancelPriceAlert(uint256 alertId) external {
        require(priceAlerts[msg.sender][alertId].active, "HiveNotification: alert not active");
        delete priceAlerts[msg.sender][alertId];
        emit PriceAlertCancelled(msg.sender, alertId);
    }

    /// @notice Check and trigger price alerts (called by oracle)
    /// @param token Token symbol
    /// @param currentPrice Current price in USD (8 decimals)
    function checkPriceAlerts(string calldata token, uint256 currentPrice) external onlyAuthorized {
        // This would iterate over subscribed users and check alerts
        // For gas efficiency, this is typically done off-chain
        // On-chain just records the event
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SEND NOTIFICATIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Send notification to a single user
    function notify(
        address user,
        EventType eventType,
        string calldata title,
        string calldata message,
        bytes calldata data
    ) external onlyAuthorized {
        _notify(user, eventType, title, message, data);
    }

    /// @notice Send notification to multiple users
    function notifyBatch(
        address[] calldata users,
        EventType eventType,
        string calldata title,
        string calldata message,
        bytes calldata data
    ) external onlyAuthorized {
        for (uint256 i = 0; i < users.length; i++) {
            _notify(users[i], eventType, title, message, data);
        }

        emit BatchNotification(users, eventType, block.timestamp, title, message, data);
    }

    /// @notice Internal notification function
    function _notify(
        address user,
        EventType eventType,
        string calldata title,
        string calldata message,
        bytes calldata data
    ) internal {
        totalNotifications++;

        Notification[] storage notifs = notifications[user];

        // Trim if at max
        if (notifs.length >= MAX_NOTIFICATIONS) {
            // Shift left (remove oldest)
            for (uint256 i = 0; i < notifs.length - 1; i++) {
                notifs[i] = notifs[i + 1];
            }
            notifs.pop();
        }

        notifs.push(Notification({
            eventType: eventType,
            timestamp: block.timestamp,
            title: title,
            message: message,
            data: data,
            read: false
        }));

        emit NotificationSent(user, eventType, block.timestamp, title, message, data);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    READ NOTIFICATIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Mark notification as read
    function markRead(uint256 index) external {
        require(index < notifications[msg.sender].length, "HiveNotification: invalid index");
        notifications[msg.sender][index].read = true;
        emit NotificationRead(msg.sender, index);
    }

    /// @notice Mark all as read
    function markAllRead() external {
        Notification[] storage notifs = notifications[msg.sender];
        for (uint256 i = 0; i < notifs.length; i++) {
            notifs[i].read = true;
        }
        emit AllNotificationsRead(msg.sender);
    }

    /// @notice Get unread count
    function getUnreadCount(address user) external view returns (uint256 count) {
        Notification[] storage notifs = notifications[user];
        for (uint256 i = 0; i < notifs.length; i++) {
            if (!notifs[i].read) count++;
        }
    }

    /// @notice Get notification count
    function getNotificationCount(address user) external view returns (uint256) {
        return notifications[user].length;
    }

    /// @notice Get notification by index
    function getNotification(address user, uint256 index) external view returns (Notification memory) {
        require(index < notifications[user].length, "HiveNotification: invalid index");
        return notifications[user][index];
    }

    /// @notice Get recent notifications
    function getRecentNotifications(address user, uint256 count) external view returns (Notification[] memory) {
        Notification[] storage notifs = notifications[user];
        uint256 len = notifs.length;

        if (len == 0) return new Notification[](0);

        uint256 start = len > count ? len - count : 0;
        uint256 resultLen = len - start;

        Notification[] memory result = new Notification[](resultLen);
        for (uint256 i = 0; i < resultLen; i++) {
            result[i] = notifs[start + i];
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    AUTHORIZED EMITTERS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Authorize contract to emit notifications
    function authorizeEmitter(address emitter) external onlyOwner {
        authorizedEmitters[emitter] = true;
        emit EmitterAuthorized(emitter);
    }

    /// @notice Revoke emitter authorization
    function revokeEmitter(address emitter) external onlyOwner {
        authorizedEmitters[emitter] = false;
        emit EmitterRevoked(emitter);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Update HiveID contract
    function setHiveID(address _hiveID) external onlyOwner {
        hiveID = IHiveID(_hiveID);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveNotification: zero address");
        owner = newOwner;
    }
}
