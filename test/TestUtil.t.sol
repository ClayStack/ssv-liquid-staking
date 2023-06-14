// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@core/LiquidToken.sol";
import "./mocks/MockDepositContract.sol";

contract TestUtil is Test {
    LiquidToken public liquidToken;
    MockDepositContract public depositContract;

    function setUp() public {
        // Consensus deposit contract
        depositContract = new MockDepositContract();

        // Deploy Liquid Token
        liquidToken = new LiquidToken("Liquid Token using SSV iETH", "iETH", address(depositContract));
    }

    function _oracleReport() internal {
        vm.warp(block.timestamp + 1 seconds);
        uint256 activeCount = depositContract.mockActiveCount();
        uint256 totalBalance = depositContract.mockActiveBalance();
        uint256 exited = depositContract.mockExitCount();
        liquidToken.oracleReport(block.timestamp, activeCount, totalBalance, exited);
    }

    function _registerValidator(uint256 _index) internal {
        bytes memory pubkey = uintToBytes(_index, 48);
        bytes memory signature = uintToBytes(_index, 96);
        bytes32 deposit_data_root = bytes32(_index);
        bytes memory withdrawal_credentials = abi.encode(address(liquidToken));
        liquidToken.registerValidator(pubkey, withdrawal_credentials, signature, deposit_data_root);
    }

    function uintToBytes(uint256 value, uint256 bytesLength) public pure returns (bytes memory) {
        bytes32 packed = keccak256(abi.encodePacked(value));
        bytes memory result = new bytes(bytesLength);
        assembly {
            mstore(add(result, 32), packed)
        }
        return result;
    }

    receive() external payable {}
}
