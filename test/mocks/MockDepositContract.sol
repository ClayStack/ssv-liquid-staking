// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@core/interfaces/IDepositContract.sol";
import "forge-std/console.sol";

// Based on official specification in https://eips.ethereum.org/EIPS/eip-165
interface ERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///  uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceId` and
    ///  `interfaceId` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}

// This is a rewrite of the Vyper Eth2.0 deposit contract in Solidity.
// It tries to stay as close as possible to the original source code.
/// @notice This is the Ethereum 2.0 deposit contract interface.
/// For more information see the Phase 0 specification under https://github.com/ethereum/eth2.0-specs
contract MockDepositContract is IDepositContract, ERC165 {
    uint constant DEPOSIT_CONTRACT_TREE_DEPTH = 32;
    // NOTE: this also ensures `deposit_count` will fit into 64-bits
    uint constant MAX_DEPOSIT_COUNT = 2 ** DEPOSIT_CONTRACT_TREE_DEPTH - 1;

    bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] branch;
    uint256 deposit_count;

    bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] zero_hashes;

    constructor() {
        // Compute hashes in empty sparse Merkle tree
        for (uint height = 0; height < DEPOSIT_CONTRACT_TREE_DEPTH - 1; height++)
            zero_hashes[height + 1] = sha256(abi.encodePacked(zero_hashes[height], zero_hashes[height]));
    }

    function get_deposit_root() external view override returns (bytes32) {
        bytes32 node;
        uint size = deposit_count;
        for (uint height = 0; height < DEPOSIT_CONTRACT_TREE_DEPTH; height++) {
            if ((size & 1) == 1) node = sha256(abi.encodePacked(branch[height], node));
            else node = sha256(abi.encodePacked(node, zero_hashes[height]));
            size /= 2;
        }
        return sha256(abi.encodePacked(node, to_little_endian_64(uint64(deposit_count)), bytes24(0)));
    }

    function get_deposit_count() external view override returns (bytes memory) {
        return to_little_endian_64(uint64(deposit_count));
    }

    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32
    ) external payable override {
        // Extended ABI length checks since dynamic types are used.
        require(pubkey.length == 48, "DepositContract: invalid pubkey length");
        require(withdrawal_credentials.length == 32, "DepositContract: invalid withdrawal_credentials length");
        require(signature.length == 96, "DepositContract: invalid signature length");

        // Check deposit amount
        require(msg.value >= 1 ether, "DepositContract: deposit value too low");
        require(msg.value % 1 gwei == 0, "DepositContract: deposit value not multiple of gwei");
        uint deposit_amount = msg.value / 1 gwei;
        require(deposit_amount <= type(uint64).max, "DepositContract: deposit value too high");

        // Emit `DepositEvent` log
        bytes memory amount = to_little_endian_64(uint64(deposit_amount));
        emit DepositEvent(
            pubkey,
            withdrawal_credentials,
            amount,
            signature,
            to_little_endian_64(uint64(deposit_count))
        );
        deposit_count += 1;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ERC165).interfaceId || interfaceId == type(IDepositContract).interfaceId;
    }

    function to_little_endian_64(uint64 value) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }

    uint256 public mockActiveCount;
    uint256 public mockExitCount;

    function mockActivate() public {
        mockActiveCount = deposit_count - mockExitCount;
    }

    function mockExit(uint256 count, address withdrawAddress, uint256 penaltiesExit) external {
        require(count <= mockActiveCount, "Not enough active validators");

        // exit the low balance validator first
        uint256 effectiveBalance = (deposit_count - mockExitCount) * 32 ether;
        uint256 balance = address(this).balance;
        uint256 penalties = balance < effectiveBalance ? effectiveBalance - balance : 0;

        require(penalties >= penaltiesExit, "Not enough penalties");
        uint256 effectiveExit = count * 32 ether;
        require(effectiveExit >= penaltiesExit, "Penalties exceed exited validators");

        uint256 amountExit = effectiveExit - penaltiesExit;
        if (amountExit != 0) {
            (bool sent, ) = payable(withdrawAddress).call{value: amountExit}("");
            require(sent, "Failed transfer exit");
        }

        mockActiveCount -= count;
        mockExitCount += count;
    }

    function mockActiveBalance() external view returns (uint256) {
        uint256 inactive = deposit_count - mockExitCount - mockActiveCount;
        uint256 inactiveBalance = inactive * 32 ether;
        uint256 totalBalance = address(this).balance;
        return totalBalance > inactiveBalance ? totalBalance - inactiveBalance : 0;
    }

    function mockRewards() external payable {}

    function mockPenalty(uint256 amount) external payable {
        (bool sent, ) = payable(address(0)).call{value: amount}("");
        require(sent, "Failed transfer rewards");
    }

    function mockDistributeRewards(address withdrawAddress, uint256 value) external payable {
        uint256 effectiveBalance = (deposit_count - mockExitCount) * 32 ether;
        uint256 balance = address(this).balance;
        uint256 rewards = balance > effectiveBalance ? balance - effectiveBalance : 0;
        require(value <= rewards && rewards > 0, "Not enough rewards");
        (bool sent, ) = payable(withdrawAddress).call{value: value}("");
        require(sent, "Failed transfer rewards");
    }
}
