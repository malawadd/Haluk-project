// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/* OpenZeppelin imports for UUPS upgradeable pattern */
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SLAEnforcerUpgradable
 * @dev An SLA enforcement contract with:
 *      1. Decentralized/Multi-Oracle approach
 *      2. Complex SLA metrics (averaged over time)
 *      3. Fee & slash distribution to a treasury
 *      4. UUPS upgradeable pattern for contract evolution
 */
contract SLAEnforcerUpgradable is Initializable, UUPSUpgradeable {
    // -------------------------------------------------------------------------
    // STRUCTS & ENUMS
    // -------------------------------------------------------------------------
    
    /**
     * @dev Node struct holds stake info, active status, and a rolling performance record index.
     */
    struct Node {
        bool registered;
        bool active;
        uint256 stake;
        uint256 delistedUntil;
        uint256 performanceRecordIndex;  // Next index to write in performanceRecords
    }
    
    /**
     * @dev A record of multiple performance metrics reported at a single point in time.
     *      - uptime: in percentage (0–100)
     *      - throughput: arbitrary scale (e.g., "tasks/hour" or a relative measure)
     *      - successRate: in percentage (0–100)
     */
    struct PerformanceRecord {
        uint256 timestamp;
        uint8 uptime;
        uint16 throughput;
        uint8 successRate;
    }

    // -------------------------------------------------------------------------
    // STATE VARIABLES
    // -------------------------------------------------------------------------
    address public owner;
    address public treasury;                      // Where slashed stakes & fees go
    IERC20Upgradeable public token;               // ERC20 token (e.g. HALUK)
    
    // SLA Parameters
    uint256 public minStakeRequired;
    uint256 public slashPercentage;
    uint256 public delistingPeriod;
    uint256 public relistFee;
    
    // Node Reward
    uint256 public baseReward;
    
    // Performance Averages
    uint256 public performanceWindow; // # of records to average (e.g., daily or weekly)

    // Node Mappings
    mapping(address => Node) public nodes;
    mapping(address => PerformanceRecord[]) public performanceRecords;

    // Oracles
    mapping(address => bool) public oracles; // Set of authorized oracle addresses
    uint256 public quorum;                  // Number of oracle reports required to finalize an update

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event NodeRegistered(address indexed node, uint256 stake);
    event NodeDelisted(address indexed node, uint256 slashAmount, uint256 delistedUntil);
    event NodeRelisted(address indexed node);
    event PerformanceReported(address indexed node, address indexed oracle, uint8 uptime, uint16 throughput, uint8 successRate);
    event PerformanceFinalized(address indexed node, uint8 uptime, uint16 throughput, uint8 successRate);
    event RewardDistributed(address indexed node, uint256 reward);
    event StakeSlashed(address indexed node, uint256 slashAmount);

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not contract owner");
        _;
    }
    
    modifier onlyOracle() {
        require(oracles[msg.sender], "Not an authorized oracle");
        _;
    }

    modifier onlyActiveNode(address _node) {
        require(nodes[_node].registered, "Node not registered");
        require(nodes[_node].active, "Node is delisted");
        _;
    }

    // -------------------------------------------------------------------------
    // UUPS UPGRADEABLE PATTERN
    // -------------------------------------------------------------------------
    /**
     * @dev Instead of a constructor, we use an initialize() function called once by the proxy.
     */
    function initialize(
        address _owner,
        address _treasury,
        address _tokenAddress,
        uint256 _minStakeRequired,
        uint256 _slashPercentage,
        uint256 _delistingPeriod,
        uint256 _relistFee,
        uint256 _baseReward,
        uint256 _performanceWindow,
        uint256 _quorum
    ) public initializer {
        __UUPSUpgradeable_init(); // Initialize parent contracts if needed

        owner = _owner;
        treasury = _treasury;
        token = IERC20Upgradeable(_tokenAddress);

        minStakeRequired = _minStakeRequired;    // e.g., 1000 * 10^18
        slashPercentage = _slashPercentage;      // e.g., 10 => 10%
        delistingPeriod = _delistingPeriod;      // e.g., 7 days
        relistFee = _relistFee;                  // e.g., 50 * 10^18
        baseReward = _baseReward;                // e.g., 100 * 10^18
        performanceWindow = _performanceWindow;  // e.g., 7 => 7 records to average
        quorum = _quorum;                        // e.g., 3 => 3 oracles needed to finalize

        // Add the owner as an oracle by default (optional)
        oracles[_owner] = true;
    }
    
    /**
     * @dev Required by UUPS pattern to authorize upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // -------------------------------------------------------------------------
    // ORACLE MANAGEMENT & PERFORMANCE REPORTING
    // -------------------------------------------------------------------------
    
    /**
     * @dev Owner can add or remove oracle addresses. 
     */
    function setOracle(address _oracle, bool _status) external onlyOwner {
        oracles[_oracle] = _status;
    }
    
    /**
     * @dev We simulate a simple multi-oracle approach by storing multiple performance
     *      reports off-chain (or in an aggregator) before finalizing one on-chain. 
     *      For demonstration, we let oracles directly call finalize. In a robust system,
     *      you might store partial reports and only finalize when enough oracles have agreed.
     */
    function reportPerformance(
        address _node, 
        uint8 _uptime, 
        uint16 _throughput, 
        uint8 _successRate
    ) external onlyOracle onlyActiveNode(_node) {
        // Emit an event for logging off-chain, aggregator can track these reports
        emit PerformanceReported(_node, msg.sender, _uptime, _throughput, _successRate);
        
        // In a real multi-oracle system, you might collect multiple reports before calling finalizePerformance.
        // For simplicity, we call finalize immediately.
        finalizePerformance(_node, _uptime, _throughput, _successRate);
    }

    /**
     * @dev Finalize the node's performance by pushing a new record. 
     *      This simulates the aggregator's job in a multi-oracle approach.
     */
    function finalizePerformance(
        address _node,
        uint8 _uptime,
        uint16 _throughput,
        uint8 _successRate
    ) internal {
        PerformanceRecord memory record = PerformanceRecord({
            timestamp: block.timestamp,
            uptime: _uptime,
            throughput: _throughput,
            successRate: _successRate
        });
        
        performanceRecords[_node].push(record);

        // In production, you might require a minimum quorum of identical or near-identical reports
        // before finalizing. For now, we assume the aggregator or majority logic is handled off-chain.

        emit PerformanceFinalized(_node, _uptime, _throughput, _successRate);
    }
    
    // -------------------------------------------------------------------------
    // REGISTRATION & STAKING
    // -------------------------------------------------------------------------
    
    /**
     * @dev Nodes stake tokens to register. 
     */
    function registerNode(uint256 _stakeAmount) external {
        require(!nodes[msg.sender].registered, "Node already registered");
        require(_stakeAmount >= minStakeRequired, "Stake below minimum required");

        bool success = token.transferFrom(msg.sender, address(this), _stakeAmount);
        require(success, "Token transfer failed");

        Node memory newNode = Node({
            registered: true,
            active: true,
            stake: _stakeAmount,
            delistedUntil: 0,
            performanceRecordIndex: 0
        });
        
        nodes[msg.sender] = newNode;
        emit NodeRegistered(msg.sender, _stakeAmount);
    }
    
    // -------------------------------------------------------------------------
    // SLA ENFORCEMENT
    // -------------------------------------------------------------------------
    
    /**
     * @dev Enforce SLA by computing the average performance over the last `performanceWindow` records.
     *      If below threshold, slash stake & delist. Otherwise, distribute baseReward.
     *      The threshold logic (e.g., "must have >= 80% average uptime and successRate") 
     *      can be implemented as you see fit.
     */
    function enforceSLA(address _node) external onlyOracle onlyActiveNode(_node) {
        (uint8 avgUptime, uint16 avgThroughput, uint8 avgSuccessRate) = _getAverages(_node);

        // Example SLA condition:
        //  - uptime >= 80
        //  - successRate >= 80
        //  - throughput can be used for additional scaling, if desired
        if (avgUptime < 80 || avgSuccessRate < 80) {
            // SLA failed -> slash stake, delist
            uint256 slashAmount = (nodes[_node].stake * slashPercentage) / 100;
            nodes[_node].stake -= slashAmount;

            // Send slashed stake to the treasury
            // If you want to "burn" it, send it to a burn address (e.g., 0xdead).
            bool success = token.transfer(treasury, slashAmount);
            require(success, "Slash transfer failed");

            emit StakeSlashed(_node, slashAmount);

            // Delist the node
            nodes[_node].active = false;
            nodes[_node].delistedUntil = block.timestamp + delistingPeriod;
            emit NodeDelisted(_node, slashAmount, nodes[_node].delistedUntil);

        } else {
            // SLA passed -> distribute baseReward
            require(token.balanceOf(address(this)) >= baseReward, "Insufficient contract balance for reward");
            bool success = token.transfer(_node, baseReward);
            require(success, "Reward transfer failed");
            emit RewardDistributed(_node, baseReward);
        }
    }

    // -------------------------------------------------------------------------
    // RE-LISTING
    // -------------------------------------------------------------------------
    
    /**
     * @dev Delisted nodes can come back online after paying a re-list fee, 
     *      once the delistingPeriod is over.
     */
    function relistNode() external {
        require(nodes[msg.sender].registered, "Node not registered");
        require(!nodes[msg.sender].active, "Node is already active");
        require(block.timestamp > nodes[msg.sender].delistedUntil, "Delisting period not over");

        // Pay the re-list fee
        bool success = token.transferFrom(msg.sender, address(this), relistFee);
        require(success, "Re-list fee transfer failed");

        // Send fee to treasury
        success = token.transfer(treasury, relistFee);
        require(success, "Fee treasury transfer failed");

        // Reactivate node
        nodes[msg.sender].active = true;
        nodes[msg.sender].delistedUntil = 0;
        emit NodeRelisted(msg.sender);
    }
    
    // -------------------------------------------------------------------------
    // INTERNAL UTILS
    // -------------------------------------------------------------------------
    
    /**
     * @dev Compute the average values of the last `performanceWindow` records for a node.
     *      If the node has fewer records, compute the average of all available records.
     */
    function _getAverages(address _node) internal view returns (uint8, uint16, uint8) {
        PerformanceRecord[] storage records = performanceRecords[_node];
        if (records.length == 0) {
            return (0, 0, 0);
        }

        uint256 startIndex = 0;
        if (records.length > performanceWindow) {
            startIndex = records.length - performanceWindow;
        }

        uint256 totalUptime = 0;
        uint256 totalThroughput = 0;
        uint256 totalSuccessRate = 0;
        uint256 count = 0;

        for (uint256 i = startIndex; i < records.length; i++) {
            totalUptime += records[i].uptime;
            totalThroughput += records[i].throughput;
            totalSuccessRate += records[i].successRate;
            count++;
        }

        // Compute simple integer-based averages
        // Be mindful of potential overflow if values or count are large.
        uint8 avgUptime = uint8(totalUptime / count);
        uint16 avgThroughput = uint16(totalThroughput / count);
        uint8 avgSuccessRate = uint8(totalSuccessRate / count);

        return (avgUptime, avgThroughput, avgSuccessRate);
    }

    // -------------------------------------------------------------------------
    // OWNER-ONLY ADMIN FUNCTIONS
    // -------------------------------------------------------------------------
    
    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setSLAParameters(
        uint256 _slashPercentage,
        uint256 _delistingPeriod,
        uint256 _relistFee,
        uint256 _baseReward,
        uint256 _performanceWindow
    ) external onlyOwner {
        require(_slashPercentage <= 100, "Invalid slash percentage");
        slashPercentage = _slashPercentage;
        delistingPeriod = _delistingPeriod;
        relistFee = _relistFee;
        baseReward = _baseReward;
        performanceWindow = _performanceWindow;
    }

    function setMinStakeRequired(uint256 _minStakeRequired) external onlyOwner {
        minStakeRequired = _minStakeRequired;
    }

    // -------------------------------------------------------------------------
    // FALLBACKS
    // -------------------------------------------------------------------------
    // Since we are using ERC20 tokens, the contract does not necessarily need
    // to handle ETH. If you want to add support for receiving ETH, you can implement
    // receive() or fallback() here, but it's optional in this context.
}
