// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TestUtil.t.sol";

contract ExitsTest is TestUtil {
    function testExitValidator() public {
        _registerValidator(0);
        _registerValidator(1);

        uint256 depositAmount = 64 ether;
        liquidToken.deposit{value: depositAmount}();
        depositContract.mockActivate();
        _oracleReport();
        uint256 exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        // withdraw
        uint256 orderId = liquidToken.withdraw(32 ether);
        assertEq(liquidToken.pendingWithdrawals(), 32 ether);

        // not possible to claim yet
        vm.expectRevert(bytes("Order not claimable"));
        liquidToken.claim(orderId);

        // admin triggers exit, and oracle confirms receipt
        depositContract.mockExit(1, address(liquidToken), 0);
        liquidToken.exitValidator();
        _oracleReport();
        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        // claims
        liquidToken.claim(orderId);
    }
}
