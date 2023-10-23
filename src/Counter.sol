// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Counter {
    uint256 public number;
    bool public isActive;

    error CoffeeBreak();

    function activate() public {
        isActive = true;
    }

    function setNumber(uint256 newNumber, bool inLuck) public {
        number = newNumber;
        if (newNumber == 0xC0FFEE && inLuck == true && isActive == true) {
            revert CoffeeBreak();
        }
    }

    function increment() public {
        number++;
    }
}