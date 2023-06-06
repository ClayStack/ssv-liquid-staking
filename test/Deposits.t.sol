// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TestUtil.t.sol";

contract DepositsTest is TestUtil {
    function testDepositToConsensus() public {
        // register validators
        _registerValidator(0);
        _registerValidator(1);
        assertEq(liquidToken.validatorNonce(), 2);

        uint256 depositAmount = 96 ether;
        liquidToken.deposit{value: depositAmount}();
        assertEq(address(liquidToken).balance, 32 ether);
        assertEq(liquidToken.depositedValidators(), 2);
        assertEq(liquidToken.activeValidators(), 0);
        assertEq(liquidToken.getPendingActivationBalance(), 64 ether);

        uint256 exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        // test active & report
        depositContract.mockActivate();
        _oracleReport();
        assertEq(liquidToken.getPendingActivationBalance(), 0);
        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);
    }
}
