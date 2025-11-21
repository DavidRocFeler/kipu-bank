// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

// import in remix

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// Para Chainlink, necesitas instalarlo primero
// npm install @chainlink/contracts
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBankSecure is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // ============ CONSTANTS ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    
    uint256 public constant PRICE_STALE_THRESHOLD = 12 hours;
    uint256 public constant MAX_PRICE_DEVIATION_PERCENT = 10; // 10%
    uint256 public constant BASIS_POINTS = 10000;

    // ============ STRUCTS ============
    struct TokenConfig {
        bool supported;
        uint256 withdrawalLimit;
        uint256 depositLimit;
        uint256 bankCap;
        address priceFeed;
        uint8 decimals;
        string symbol;
        uint256 lastPrice;
        uint256 priceUpdatedAt;
        uint256 priceDeviationThreshold;
    }

    struct UserDailyLimits {
        uint256 depositsUSD;
        uint256 withdrawalsUSD;
        uint256 lastActivityDate;
    }

    // ============ STATE VARIABLES ============
    AggregatorV3Interface public ethUsdPriceFeed;
    
    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(address => uint256)) public tokenBalances;
    mapping(address => uint256) public tokenTotalBalances;
    mapping(address => UserDailyLimits) public userDailyLimits;
    
    address[] public supportedTokens;

    // ============ EVENTS ============
    event Deposited(
        address indexed user, 
        address indexed token, 
        uint256 amount, 
        uint256 usdValue,
        uint256 timestamp
    );
    
    event Withdrawn(
        address indexed user, 
        address indexed token, 
        uint256 amount, 
        uint256 usdValue,
        uint256 timestamp
    );
    
    event TokenSupported(address indexed token, address priceFeed);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event EmergencyPaused(address indexed by, uint256 timestamp);
    event EmergencyUnpaused(address indexed by, uint256 timestamp);

    // ============ ERRORS ============
    error ExceedsBankCap();
    error ExceedsWithdrawalThreshold();
    error ExceedsDepositThreshold();
    error InsufficientBalance();
    error Unauthorized();
    error ZeroAmount();
    error TokenNotSupported();
    error InvalidToken();
    error PriceFeedNotAvailable();
    error TransferFailed();
    error InsufficientAllowance();
    error InvalidPriceFeed();
    error StalePrice();
    error PriceDeviationExceeded();
    error ContractPaused();

    // ============ MODIFIERS ============
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }
    
    modifier onlySupportedToken(address token) {
        if (!tokenConfigs[token].supported && token != address(0)) 
            revert TokenNotSupported();
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(
        address admin,
        address _ethUsdPriceFeed
    ) {
        // ✅ INICIALIZACIÓN IMPLÍCITA DE CONTRATOS PADRE
        // AccessControl, ReentrancyGuard y Pausable se inicializan automáticamente
        // ya que no tienen constructores con parámetros
        
        // Configurar roles
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(RISK_MANAGER_ROLE, admin);
        
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(RISK_MANAGER_ROLE, ADMIN_ROLE);
        
        // Validar price feed
        _validatePriceFeed(_ethUsdPriceFeed);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        
        // Configurar ETH
        _setupToken(
            address(0), 
            10 ether, 
            50 ether, 
            1000 ether, 
            _ethUsdPriceFeed, 
            18, 
            "ETH",
            500 // 5% deviation threshold
        );
    }

    // ============ TOKEN MANAGEMENT ============
    function supportToken(
        address token,
        uint256 withdrawalLimit,
        uint256 depositLimit,
        uint256 bankCap,
        address priceFeed,
        uint256 deviationThreshold
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused nonReentrant {
        require(token != address(0), "Invalid token");
        
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            string memory symbol = IERC20Metadata(token).symbol();
            
            _setupToken(
                token, 
                withdrawalLimit, 
                depositLimit, 
                bankCap, 
                priceFeed, 
                decimals, 
                symbol,
                deviationThreshold
            );
            
            supportedTokens.push(token);
            emit TokenSupported(token, priceFeed);
        } catch {
            revert InvalidToken();
        }
    }

    function _setupToken(
        address token,
        uint256 withdrawalLimit,
        uint256 depositLimit,
        uint256 bankCap,
        address priceFeed,
        uint8 decimals,
        string memory symbol,
        uint256 deviationThreshold
    ) internal {
        if (priceFeed != address(0)) {
            _validatePriceFeed(priceFeed);
        }
        
        tokenConfigs[token] = TokenConfig({
            supported: true,
            withdrawalLimit: withdrawalLimit,
            depositLimit: depositLimit,
            bankCap: bankCap,
            priceFeed: priceFeed,
            decimals: decimals,
            symbol: symbol,
            lastPrice: 0,
            priceUpdatedAt: 0,
            priceDeviationThreshold: deviationThreshold
        });
        
        if (priceFeed != address(0)) {
            _updateTokenPrice(token);
        }
    }

    // ============ PRICE MANAGEMENT ============
    function _validatePriceFeed(address priceFeed) internal view {
        if (priceFeed == address(0)) revert InvalidPriceFeed();
        
        try AggregatorV3Interface(priceFeed).decimals() returns (uint8) {
            // Price feed válido
        } catch {
            revert InvalidPriceFeed();
        }
    }

    function _updateTokenPrice(address token) internal {
        TokenConfig storage config = tokenConfigs[token];
        if (config.priceFeed == address(0)) return;
        
        (, int256 price, , uint256 updatedAt, ) = AggregatorV3Interface(config.priceFeed)
            .latestRoundData();
        
        // ✅ VALIDAR PRECIO OBSOLETO
        if (block.timestamp - updatedAt > PRICE_STALE_THRESHOLD) {
            revert StalePrice();
        }
        
        uint256 newPrice = uint256(price);
        
        // ✅ VALIDAR DESVIACIÓN DE PRECIO (si existe precio anterior)
        if (config.lastPrice > 0 && config.priceDeviationThreshold > 0) {
            uint256 deviation = _calculatePriceDeviation(config.lastPrice, newPrice);
            if (deviation > config.priceDeviationThreshold) {
                revert PriceDeviationExceeded();
            }
        }
        
        config.lastPrice = newPrice;
        config.priceUpdatedAt = updatedAt;
        
        emit PriceUpdated(token, newPrice, updatedAt);
    }

    function _calculatePriceDeviation(uint256 oldPrice, uint256 newPrice) 
        internal 
        pure 
        returns (uint256) 
    {
        if (oldPrice == 0) return 0;
        
        uint256 deviation;
        if (newPrice > oldPrice) {
            deviation = ((newPrice - oldPrice) * BASIS_POINTS) / oldPrice;
        } else {
            deviation = ((oldPrice - newPrice) * BASIS_POINTS) / oldPrice;
        }
        
        return deviation;
    }

    // ============ DEPOSIT/WITHDRAW ============
    function depositETH() external payable nonZeroAmount(msg.value) whenNotPaused nonReentrant {
        // ✅ VALIDAR LÍMITES ANTES DE _deposit
        TokenConfig memory config = tokenConfigs[address(0)];
        require(msg.value <= config.depositLimit, "Exceeds deposit limit");
        require(tokenTotalBalances[address(0)] + msg.value <= config.bankCap, "Exceeds bank cap");
        
        _deposit(address(0), msg.value);
    }

    function depositToken(address token, uint256 amount) 
        external 
        nonZeroAmount(amount) 
        onlySupportedToken(token) 
        whenNotPaused 
        nonReentrant 
    {
        // ✅ VALIDAR LÍMITES ANTES DE TRANSFER
        TokenConfig memory config = tokenConfigs[token];
        require(amount <= config.depositLimit, "Exceeds deposit limit");
        require(tokenTotalBalances[token] + amount <= config.bankCap, "Exceeds bank cap");
        
        // ✅ USAR SafeERC20 PARA TRANSFERENCIAS SEGURAS
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, amount);
    }

    function _deposit(address token, uint256 amount) internal {
        _resetDailyLimitsIfNeeded(msg.sender);
        _updateTokenPrice(token);
        
        uint256 usdValue = _getUSDValue(token, amount);
        UserDailyLimits storage limits = userDailyLimits[msg.sender];
        
        // ✅ LÍMITES DIARIOS EN USD
        require(limits.depositsUSD + usdValue <= _getUserDailyDepositLimit(), "Exceeds daily deposit limit");
        
        tokenBalances[msg.sender][token] += amount;
        tokenTotalBalances[token] += amount;
        limits.depositsUSD += usdValue;
        
        emit Deposited(msg.sender, token, amount, usdValue, block.timestamp);
    }

    function withdrawETH(uint256 amount) 
        external 
        nonZeroAmount(amount) 
        whenNotPaused 
        nonReentrant 
    {
        _withdraw(address(0), amount);
        
        // ✅ USAR sendValue PARA TRANSFERENCIAS SEGURAS DE ETH
        payable(msg.sender).sendValue(amount);
    }

    function withdrawToken(address token, uint256 amount) 
        external 
        nonZeroAmount(amount) 
        onlySupportedToken(token) 
        whenNotPaused 
        nonReentrant 
    {
        _withdraw(token, amount);
        
        // ✅ USAR SafeERC20 PARA TRANSFERENCIAS SEGURAS
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function _withdraw(address token, uint256 amount) internal {
        TokenConfig memory config = tokenConfigs[token];
        
        require(tokenBalances[msg.sender][token] >= amount, "Insufficient balance");
        require(amount <= config.withdrawalLimit, "Exceeds withdrawal limit");
        
        _resetDailyLimitsIfNeeded(msg.sender);
        _updateTokenPrice(token);
        
        uint256 usdValue = _getUSDValue(token, amount);
        UserDailyLimits storage limits = userDailyLimits[msg.sender];
        
        // ✅ LÍMITES DIARIOS EN USD
        require(limits.withdrawalsUSD + usdValue <= _getUserDailyWithdrawalLimit(), "Exceeds daily withdrawal limit");
        
        tokenBalances[msg.sender][token] -= amount;
        tokenTotalBalances[token] -= amount;
        limits.withdrawalsUSD += usdValue;
        
        emit Withdrawn(msg.sender, token, amount, usdValue, block.timestamp);
    }

    // ============ LIMIT MANAGEMENT ============
    function _resetDailyLimitsIfNeeded(address user) internal {
        UserDailyLimits storage limits = userDailyLimits[user];
        uint256 today = block.timestamp / 1 days;
        
        if (limits.lastActivityDate < today) {
            limits.depositsUSD = 0;
            limits.withdrawalsUSD = 0;
            limits.lastActivityDate = today;
        }
    }

    function _getUSDValue(address token, uint256 amount) internal view returns (uint256) {
        TokenConfig memory config = tokenConfigs[token];
        
        if (config.priceFeed == address(0) || config.lastPrice == 0) {
            return 0; // No price available
        }
        
        require(block.timestamp - config.priceUpdatedAt <= PRICE_STALE_THRESHOLD, "Stale price");
        
        uint8 priceFeedDecimals = AggregatorV3Interface(config.priceFeed).decimals();
        
        // ✅ CONVERSIÓN SEGURA DE DECIMALES
        uint256 normalizedAmount = (amount * 1e18) / (10 ** config.decimals);
        uint256 usdValue = (normalizedAmount * config.lastPrice) / (10 ** priceFeedDecimals);
        
        return usdValue;
    }
    
    function _getUserDailyDepositLimit() internal pure returns (uint256) {
        return 10000 * 1e8; // $10,000
    }
    
    function _getUserDailyWithdrawalLimit() internal pure returns (uint256) {
        return 5000 * 1e8; // $5,000
    }

    // ============ EMERGENCY FUNCTIONS ============
    function emergencyPause() external onlyRole(ADMIN_ROLE) {
        _pause();
        emit EmergencyPaused(msg.sender, block.timestamp);
    }
    
    function emergencyUnpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender, block.timestamp);
    }
    
    function emergencyWithdraw(address token, address to) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) {
            payable(to).sendValue(address(this).balance);
        } else {
            IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
        }
    }

    // ============ VIEW FUNCTIONS ============
    function getBalance(address user, address token) 
        external 
        view 
        returns (uint256) 
    {
        return tokenBalances[user][token];
    }
    
    function getUSDValue(address token, uint256 amount) 
        external 
        view 
        returns (uint256) 
    {
        return _getUSDValue(token, amount);
    }
    
    function isPriceFresh(address token) external view returns (bool) {
        return block.timestamp - tokenConfigs[token].priceUpdatedAt <= PRICE_STALE_THRESHOLD;
    }

    // ============ FALLBACK ============
    receive() external payable {
        // ✅ LÓGICA SIMPLIFICADA CON VALIDACIÓN
        if (msg.value > 0 && !paused()) {
            TokenConfig memory config = tokenConfigs[address(0)];
            if (msg.value <= config.depositLimit && 
                tokenTotalBalances[address(0)] + msg.value <= config.bankCap) {
                _deposit(address(0), msg.value);
            }
        }
    }
}