// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TestUtil.t.sol";

contract LiquidTokenTest is TestUtil {
    function testDeposit() public {
        uint256 depositAmount = 10 ether;
        liquidToken.deposit{value: depositAmount}();
        assertEq(liquidToken.balanceOf(address(this)), depositAmount);
        assertEq(address(liquidToken).balance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 10 ether;
        liquidToken.deposit{value: depositAmount}();

        uint256 withdrawAmount = 5 ether;
        liquidToken.withdraw(withdrawAmount);
        assertEq(liquidToken.balanceOf(address(this)), depositAmount - withdrawAmount);
        assertEq(address(liquidToken).balance, depositAmount);
    }

    function testClaim() public {
        uint256 depositAmount = 10 ether;
        liquidToken.deposit{value: depositAmount}();

        uint256 withdrawAmount = 5 ether;
        uint256 orderId = liquidToken.withdraw(withdrawAmount);

        uint256 balanceBefore = address(this).balance;
        liquidToken.claim(orderId);
        assertEq(liquidToken.balanceOf(address(this)), depositAmount - withdrawAmount);
        assertEq(address(this).balance, balanceBefore + withdrawAmount);
    }

    function testExchangeRate() public {
        uint256 exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        uint256 depositAmount = 10 ether;
        liquidToken.deposit{value: depositAmount}();
        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        uint256 withdrawAmount = 5 ether;
        liquidToken.withdraw(withdrawAmount);
        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1 ether);

        // increase by 20 %
        uint256 extraAmount = 1 ether;
        (bool success, ) = address(liquidToken).call{value: extraAmount}("");
        require(success, "Failed to send extra amount");
        exchangeRate = liquidToken.getExchangeRate();
        assertEq(exchangeRate, 1.2 ether);
    }
}
