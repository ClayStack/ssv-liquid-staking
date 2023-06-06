// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TestUtil.t.sol";

contract DepositsTest is TestUtil {
    function testPenalties() public {
        _registerValidator(0);

        uint256 depositAmount = 32 ether;
        liquidToken.deposit{value: depositAmount}();
        depositContract.mockActivate();
        _oracleReport();
        uint256 exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        // apply penalties 10%
        depositContract.mockPenalty(16 ether);
        _oracleReport();

        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 0.5 ether);
    }
}
