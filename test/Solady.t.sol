// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Solady.sol";

contract SoladyTest is Test {
    /// @dev The scalar of ETH and most ERC20s.
    uint256 internal constant WAD = 1e18;

    function testMulWad(uint256 x, uint256 y) public {
        if(y == 0 || x <= type(uint256).max / y) {
            uint256 zSpec = (x * y) / WAD;
            uint256 zImpl = Solady.mulWad(x, y);
            assertEq(zImpl, zSpec);
        } else {
            vm.expectRevert();
            Solady.mulWad(x, y);
        }
    }
}


