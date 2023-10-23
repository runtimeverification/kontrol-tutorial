// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract Examples is Test {
    uint256 constant MAX_INT = (2 ** 256) - 1;
    uint constant WAD = 10 ** 18;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / WAD;
    }

    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = (x * WAD) / y;
    }

    function test_wmul_increasing_overflow(uint a, uint b) public {
        uint c = wmul(a, b);
        assertTrue(a < c && b < c);
    }

    function test_wmul_increasing_no_overflow(uint a, uint b) public {
        if (b <= MAX_INT / a) {
            uint c = wmul(a, b);
            assertTrue(a < c && b < c);
        }
    }

    function test_wmul_increasing_gt_one(uint a, uint b) public {
        if (WAD < a && WAD < b) {
            if (b <= MAX_INT / a) {
                uint c = wmul(a, b);
                assertTrue(a < c && b < c);
            }
        }
    }

    function test_wmul_weakly_increasing_positive(uint a, uint b) public {
        if (0 < a && 0 < b) {
            if (b <= MAX_INT / a) {
                uint c = wmul(a, b);
                assertTrue(a <= c && b <= c);
            }
        }
    }
}