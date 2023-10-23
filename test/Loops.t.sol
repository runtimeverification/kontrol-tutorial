// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract LoopsTest is Test {
    function sum_N(uint n) public returns (uint) {
        vm.assume(n <= 51816696836262767);

        uint s = 0;
        while (0 < n) {
            s = s + n;
            n = n - 1;
        }
        return s;
    }

    function test_sum_10() public returns (uint) {
        return sum_N(10);
    }
}





