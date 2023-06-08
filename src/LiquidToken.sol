// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IDepositContract.sol";

contract LiquidToken is ERC20, ReentrancyGuard {
    /// @notice Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant DEPOSIT_SIZE = 32 ether;

    /// @notice WithdrawOrder struct
    /// @param amount : Total amount ETH expected from from ethereum.
    /// @param claimed : True if the withdraw has been claimed.
    struct WithdrawOrder {
        uint amount;
        bool claimed;
    }

    /// @notice Validator struct
    /// @param pubkey : Public key of the validator.
    /// @param withdrawal_credentials : Withdrawal credentials of the validator.
    /// @param signature : Signature of the validator.
    /// @param deposit_data_root : Deposit data root of the validator.
    struct Validator {
        bytes pubkey;
        bytes withdrawal_credentials;
        bytes signature;
        bytes32 deposit_data_root;
        bool active;
    }

    /// @notice Instance of deposit contract.
    IDepositContract immutable depositContract;

    /// @notice Address of report oracle
    address public oracle;

    /// @notice Address of admin
    address public admin;

    /// @notice Oracle report timestamp
    uint256 public oracleReportTimestamp;

    /// @notice Nonce of validators ids registered
    uint256 public validatorNonce;

    /// @notice Number of deposited validators
    uint256 public depositedValidators;

    /// @notice Number of validators active in the Consensus Layer state
    uint256 public activeValidators;

    /// @notice Number of exited validators
    uint256 public exitedValidators;

    /// @notice Total balance on active validators in the Consensus Layer state
    uint256 public activeValidatorsBalance;

    /// @notice Mapping of node ids to validator data.
    mapping(uint256 => Validator) public validators;

    /// @notice Mapping of pubkey of validator to validator id.
    mapping(bytes => uint256) public registeredValidator;

    /// @notice Total amount of Ether pending to be claimed from withdraws.
    uint256 public pendingWithdrawals;

    /// @notice Linear incremental order nonce. Increases by one after each withdraw request.
    uint256 private orderNonce;

    /// @notice Mapping of all unstaking withdraw order by users.
    mapping(address => mapping(uint256 => WithdrawOrder)) public withdrawOrders;

    /// @notice Initializes the values for `name`, `symbol`.
    /// @dev The default value of `decimals` is 18.
    /// @param _name : Name of the token.
    /// @param _symbol : Symbol of the token.
    /// @param _depositContract : Address of the deposit contract.
    constructor(string memory _name, string memory _symbol, address _depositContract) ERC20(_name, _symbol) {
        require(_depositContract != address(0), "Invalid depositContract address");
        oracle = msg.sender;
        admin = msg.sender;
        depositContract = IDepositContract(_depositContract);
    }

    /** USER OPERATIONS **/

    /// @notice Sends Token to contract and mints liquidToken to msg.sender.
    /// @return amountToMint of liquidToken minted
    function deposit() external payable nonReentrant returns (uint256 amountToMint) {
        require(msg.value > 0, "Invalid Amount");
        amountToMint = _exchangeToken(msg.value);
        _mint(msg.sender, amountToMint);

        // deposit to consensus layer
        uint256 currentBalance = address(this).balance;
        if (currentBalance > pendingWithdrawals) {
            uint256 validatorCount = (currentBalance - pendingWithdrawals) / DEPOSIT_SIZE;
            if (validatorCount > 0) {
                _depositConsensus(validatorCount);
            }
        }
    }

    /// @notice Burns liquidToken from user and starts unstaking process from Ethereum
    /// @param _amount Amount of liquidToken to be withdrawn.
    /// @return id of the withdraw order.
    function withdraw(uint _amount) external nonReentrant returns (uint256 id) {
        require(_amount > 0, "Invalid Amount");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 amountTokenWithdraw = _exchangeLiquidToken(_amount);
        require(amountTokenWithdraw != 0, "Invalid token amount");

        _burn(msg.sender, _amount);

        pendingWithdrawals += amountTokenWithdraw;

        id = ++orderNonce;
        withdrawOrders[msg.sender][id] = WithdrawOrder({amount: amountTokenWithdraw, claimed: false});
    }

    /// @notice Allows the user to claim an order.
    /// @param _orderId : Id of the order to be claimed.
    function claim(uint256 _orderId) external nonReentrant {
        require(!withdrawOrders[msg.sender][_orderId].claimed, "Order already claimed");
        require(withdrawOrders[msg.sender][_orderId].amount <= address(this).balance, "Order not claimable");

        withdrawOrders[msg.sender][_orderId].claimed = true;
        pendingWithdrawals -= withdrawOrders[msg.sender][_orderId].amount;

        //slither-disable-next-line low-level-calls
        (bool success, ) = msg.sender.call{value: withdrawOrders[msg.sender][_orderId].amount}("");
        require(success, "Transfer of funds to user failed");
    }

    /// @notice Returns the current exchange rate.
    function getExchangeRate() external view returns (uint256) {
        return _exchangeLiquidToken(PRECISION);
    }

    /// @notice Returns amount of liquidTokens for given `_amountToken`.
    /// @param _amountToken : Amount of Token.
    /// @return Amount of liquidTokens
    function _exchangeToken(uint256 _amountToken) internal view returns (uint256) {
        uint256 totalLiquidToken = totalSupply();
        uint256 currentDeposits = _getDeposits();
        if (totalLiquidToken != currentDeposits && currentDeposits != 0 && totalLiquidToken != 0) {
            return (_amountToken * totalLiquidToken) / currentDeposits;
        } else {
            return _amountToken;
        }
    }

    /// @notice Returns amount of Token for given `_amount`.
    /// @param _amount : Amount of liquidToken.
    /// @return Amount of Tokens
    function _exchangeLiquidToken(uint256 _amount) internal view returns (uint256) {
        uint256 totalLiquidToken = totalSupply();
        uint256 currentDeposits = _getDeposits();
        if (totalLiquidToken != currentDeposits && totalLiquidToken != 0 && currentDeposits != 0) {
            return (_amount * currentDeposits) / totalLiquidToken;
        } else {
            return _amount;
        }
    }

    /// @notice Returns the current deposits adjusting for withdrawals and validators.
    function _getDeposits() internal view returns (uint256) {
        return address(this).balance + activeValidatorsBalance + getPendingActivationBalance() - pendingWithdrawals;
    }

    /** STAKING OPERATIONS **/

    /// @notice Registers a validator with the specified parameters.
    /// @param _pubkey The public key(s) of the validator.
    /// @param _withdrawal_credentials The withdrawal credentials of the validator.
    /// @param _signature The signature(s) of the validator.
    /// @param _deposit_data_root The deposit data root(s) of the validator.
    /// @return A boolean indicating whether the registration was successful.
    function registerValidator(
        bytes calldata _pubkey,
        bytes calldata _withdrawal_credentials,
        bytes calldata _signature,
        bytes32 _deposit_data_root
    ) external nonReentrant returns (bool) {
        require(msg.sender == admin, "Only admin can register validator");
        require(_pubkey.length == 48, "Invalid pubkey length");
        require(_withdrawal_credentials.length == 32, "Invalid withdrawal_credentials length");
        require(address(uint160(bytes20(_withdrawal_credentials[12:]))) == address(this), "Invalid withdrawal address");
        require(_signature.length == 96, "Invalid signature length");

        Validator memory validator = validators[registeredValidator[_pubkey]];
        require(!validator.active, "Pubkey already registered");

        uint256 id = ++validatorNonce;
        validators[id] = Validator(_pubkey, _withdrawal_credentials, _signature, _deposit_data_root, true);
        registeredValidator[_pubkey] = id;

        return true;
    }

    /// @notice Deposit to consensus layer number of validators if available.
    /// @param _validatorCount : Number of validators to deposit.
    function _depositConsensus(uint256 _validatorCount) internal {
        // adjust count on available validators
        uint256 availableCount = validatorNonce - depositedValidators;
        _validatorCount = _validatorCount > availableCount ? availableCount : _validatorCount;

        for (uint256 i = 0; i < _validatorCount; i++) {
            Validator memory validator = _selectNextValidator();

            //slither-disable-next-line reentrancy-eth
            depositContract.deposit{value: DEPOSIT_SIZE}(
                validator.pubkey,
                validator.withdrawal_credentials,
                validator.signature,
                validator.deposit_data_root
            );
        }
    }

    /// @notice Sequential validator selection
    function _selectNextValidator() internal returns (Validator memory validator) {
        uint256 id = ++depositedValidators;
        validator = validators[id];
        require(validator.pubkey.length == 48, "Next validator invalid");
    }

    /// @notice Returns the number of validators to deposit
    function getValidatorsCapacity() external view returns (uint256) {
        return validatorNonce - depositedValidators;
    }

    /// @notice Returns the amount of validators pending activation
    function getPendingActivationBalance() public view returns (uint256) {
        return (depositedValidators - activeValidators - exitedValidators) * DEPOSIT_SIZE;
    }

    /** NETWORK ORACLES **/

    /// @notice Consensus layer oracle report on validators and balances
    /// @param _reportTimestamp : Timestamp of the report.
    /// @param _validatorsCount : Number of validators on Consensus Layer.
    /// @param _validatorsBalance: Total balance of active validators on Consensus Layer.
    /// @param _validatorsExited: Number of validators exited.
    function oracleReport(
        uint256 _reportTimestamp,
        uint256 _validatorsCount,
        uint256 _validatorsBalance,
        uint256 _validatorsExited
    ) external nonReentrant {
        require(msg.sender == oracle, "Invalid oracle");
        require(_reportTimestamp > oracleReportTimestamp, "Invalid reportTimestamp");
        require(_validatorsCount <= depositedValidators, "Invalid validatorsCount");
        require(
            _validatorsExited <= depositedValidators && _validatorsExited >= exitedValidators,
            "Invalid validatorsExited"
        );

        // Update report
        oracleReportTimestamp = _reportTimestamp;
        activeValidators = _validatorsCount;
        activeValidatorsBalance = _validatorsBalance;
        exitedValidators = _validatorsExited;

        // emit event
        emit OracleReportEvent(activeValidators, activeValidatorsBalance, exitedValidators);
    }

    /** ADMIN **/

    /// @notice Set Oracle address to `_oracle`.
    /// @param _oracle : Address of the oracle.
    function setOracle(address _oracle) external {
        require(msg.sender == admin, "Only admin can set oracle");
        require(_oracle != address(0), "Invalid oracle address");
        oracle = _oracle;
    }

    /// @notice Set Admin address to `_admin`.
    /// @param _admin : Address of the admin.
    function setAdmin(address _admin) external {
        require(msg.sender == admin, "Only admin can set admin");
        require(_admin != address(0), "Invalid admin address");
        admin = _admin;
    }

    receive() external payable {}

    /** EVENTS **/

    /// @notice Event for oracle report
    event OracleReportEvent(uint256 activeValidators, uint256 activeValidatorsBalance, uint256 exitedValidators);
}
