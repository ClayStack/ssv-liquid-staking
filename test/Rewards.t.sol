// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TestUtil.t.sol";

contract DepositsTest is TestUtil {
    function testRewards() public {
        _registerValidator(0);

        uint256 depositAmount = 32 ether;
        liquidToken.deposit{value: depositAmount}();
        depositContract.mockActivate();
        _oracleReport();
        uint256 exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        // generate rewards 10%
        depositContract.mockRewards{value: 3.2 ether}();
        _oracleReport();

        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1.1 ether);
    }
}
