# Kontrol Tutorial

This repository contains smart contracts and instructions for the Kontrol tutorial. 

## Installation of Kontrol

The easiest way to install Kontrol is via `kup`:
```shell
bash <(curl https://kframework.org/install)
kup install kontrol
```
You can update Kontrol with:

```shell
kup update kontrol
```

And list available versions with:

```shell
kup list
```

This will take care of all the dependencies and specific versions used by Kontrol. The tutorial will be done using VS Code but please feel to use any editor you prefer. For VS Code users, you can install the ["K Framework" extension](https://marketplace.visualstudio.com/items?itemName=RuntimeVerification.k-vscode) to help you with editing the code.

To install Foundry separately, run
```sh
curl -L https://foundry.paradigm.xyz | bash
```
followed by 
```sh
foundryup
```

You can check the installed version of Foundry via
```sh
forge --version
```

## Hands-on Exercises

### K1. Fuzzing `Counter`

To create a Foundry project, create a new directory
```sh
mkdir foundry-project && cd foundry-project
```
and initialize a new Foundry project with the appropriate structure by running
```sh
forge init --no-commit
```
To fuzz the existing tests, e.g., `testFuzz_SetNumber(uint256 x)` run
```sh
forge test
```

Let's check if Foundry can correcty detect a failing test. Add the following simple test to `Counter.t.sol`:
```solidity
   function test_failure(uint256 x) public {
        if (x == 4) {
            assert(false);
        }
   }
```
`forge test` should correctly report the failure and produce a counterexample (`x = 4`). Let's make the counterexample more challenging to identify by making a constant bigger (e.g., `4` -> `421`). Most of the time, Foundry cannot identify the failure within default 256 runs. The number of runs can be increased by adding the corresponding property to the `foundry.toml` file:
```
[fuzz]
runs = 65536
```
Other configuration options are available in Foundry docs: https://github.com/foundry-rs/foundry/blob/master/crates/config/README.md#all-options.

### K2. Verifying `Counter`


Now, let's make the test even more complex. Let's rewrite the `Counter` contract, adding an additional parameter `bool inLuck` to the `setNumber` function as well as a custom `error`:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Counter {
    uint256 public number;
    bool public isActive;

    error CoffeeBreak();

    function setNumber(uint256 newNumber, bool inLuck) public {
        number = newNumber;
        if (newNumber == 0xC0FFEE && inLuck == true) {
            revert CoffeeBreak();
        }
    }

    function increment() public {
        number++;
    }
}
```
Let's also modify the `testFuzz_SetNumber` to reflect this change:
```solidity
   function testFuzz_SetNumber(uint256 x, bool inLuck) public {
       counter.setNumber(x, inLuck);
       assertEq(counter.number(), x);
   }
```
Now, the test should fail if `x` equals `0xC0FFEE` and `inLuck` is `true`. Run `forge test` to run another fuzzing campaign. Most of the time, Foundry does not report this test as failing even with the increased number of runs.

Symbolic testing performed by `kontrol`, however, is well-suited for identifying this violation. To kompile the project, run
```
kontrol build
```
Now, to verify this test, you can run 
```sh
kontrol prove --test CounterTest.testSetNumber \
              --use-booster \
              --counterexample-information
```
`kontrol` should report the failure and report the corresponding counterexample.

You can also examine the corresponding KCFG (K Control-Flow Graph) in the interactive viewer via
```
kontrol view-kcfg –-test CounterTest.testSetNumber
```
The list of proofs and their statuses is available through
```
kontrol list
```

### K3. Verifying `Counter` with Cheatcodes

To make analysis and verification of `Counter` even more challenging, let's add another variable `isActive` to the `Counter` contract and add this variable to the condition checked in `setNumber`:
```solidity
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
```
`isActive` is a state variable, which, in Solidity, is `false` by default. To make it `true`, one should called `activate()` function. In Foundry, that function should have been added to the test or a `setUp` function explicitly.

Kontrol provides a solution that reduces the number of function calls and allows for more exhaustive verification by letting the user assume that the storage is _symbolic_. This is available through Kontrol-specific cheatcodes, which can be installed as follows:
```sh
forge install runtimeverification/kontrol-cheatcodes --no-commit
``` 

Once the `KontrolCheats` cheatcode library is installed, it can be used as follows:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Counter.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

contract CounterTest is Test, KontrolCheats {
   Counter public counter;

   function setUp() public {
       counter = new Counter();
       counter.setNumber(0, false);
   }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

   function testFuzz_SetNumber(uint256 x, bool inLuck) public {
       // counter.activate();
       kevm.symbolicStorage(address(counter));
       counter.setNumber(x, inLuck);
       assertEq(counter.number(), x);
   }
}
``` 
Here, `kevm.symbolicStorage(address(counter));` indicates that the storage variables in the contract deployed at address `counter` are symbolic — therefore, we will be considering the case of `inActive` being `true`.

Re-run `kontrol build --rekompile && kontrol prove --reinit --use-booster --test CounterTest.testFuzz_SetNumber` to check.

### K4. Verifying `Solady`

Let's look at a function that belongs to [Solady](https://github.com/Vectorized/solady/tree/main) — a highly-optimized math library written in Solidity and inline-assembly. The `mulWad` function performes fixed-point multiplication, which is commonly used in Solidity contracts:
```solidity
library Solady {
    /// @dev The scalar of ETH and most ERC20s.
    uint256 internal constant WAD = 1e18;

    /// @dev Equivalent to `(x * y) / WAD` rounded down.
    function mulWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to `require(y == 0 || x <= type(uint256).max / y)`.
            if mul(y, gt(x, div(not(0), y))) {
                mstore(0x00, 0xbac65e5b) // `MulWadFailed()`.
                revert(0x1c, 0x04)
            }
            z := div(mul(x, y), WAD)
        }
    }
}
```

With Kontrol, we can verify the equivalence between the hard-to-read assembly and Solidity code, using the following test:
```solidity
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
```
However, if we run `kontrol build && kontrol prove --test SoladyTest.testMulWad --use-booster`, it will report this test as failing.

The inspection of the corresponding KCFG (`kontrol view-kcfg --test SoladyTest.testMulWad
`) shows that the branching condition leading to the failing node corresponds to the `if`-statement of the `mulWad` function:
```
chop ( ( VV1_y_114b9705:Int *Int bool2Word ( ( maxUInt256 /Int VV1_y_114b9705:Int) <Int VV0_x_114b9705:Int ) ) ) ==Int 0
```

Considering that `chop(x)` corresponds to `x mod 2^256`, it can be simplified to the following expression, which is equivalent to `y == 0 || types(uint256).max / y >= x`:
```
(y * bool2Word((maxUInt256 / y) < x) mod 2^265 == 0
```
where `bool2Word` is a function taking a boolean variable and converting it into an EVM word (`true` to `1` and `false` to `0`).

By inspecting the path conditions in the failing node, we'll identify the following (simplified) conditions:
1. `y != 0`
2. `x <= maxUInt256 / y`
3. `y * bool2Word(maxUInt256 / y < x)) != 0`

While it's clear that conditions 1 and 2 imply that condition 3 is `false`, there's a reasoning gas that doesn't allow Kontrol to conclude that this path is infeasible.

To bridge this gap, let's add the following file with _lemmas_ that instruct `bool2Word` to simplify its boolean arguments:
```
requires "evm.md"
requires "foundry.md"

module DEMO-LEMMAS
    imports BOOL
    imports FOUNDRY
    imports INFINITE-GAS
    imports INT-SYMBOLIC

    rule bool2Word ( X ) => 1 requires X         [simplification]
    rule bool2Word ( X ) => 0 requires notBool X [simplification]

endmodule
```
Now, add this lemmas to the project kompilation by running
```
kontrol build --rekompile --require ./lemmas.k --module-import SoladyTest:DEMO-LEMMAS
```
And re-run the proof which should now be passing:
```
kontrol prove --test SoladyTest.testMulWad --use-booster --reinit
```

### K5. Verifying `Loops` with Invariants

Consider the following test with two functions:
```solidity
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
```

The `sum_N` function computes sum of the first (arbitrary) `N` numbers. `test_sum_10` successfully computes this sum for `10` in less than a minute:
```
kontrol prove --test LoopsTest.test_sum_10 --use-booster
```

However, when run on `sum_N`, it would take much longer for Kontrol to explore `51816696836262767` iterations. One solution available in Kontrol is _bounded_ exploration. The bound for loop iterations can be provided as
```
kontrol prove --test LoopsTest.sum_N --bmc-depth 3 --use-booster
```

Alternatively, we can also supply a loop invariant as a rule (i.e., a lemma) similarly to how we did that in the previous exercise:
```
requires "../contracts.k"

module SUM-TO-N-INVARIANT

  imports LoopsTest-CONTRACT

  rule N xorInt maxUInt256 => maxUInt256 -Int N 
  requires #rangeUInt(256, N)
  [simplification]

  rule [foundry-sum-to-n-loop-invariant]:
  <kevm>
    <k>
      ((JUMPI 1432 CONDITION) => JUMP 1432)
      ~> #pc [ JUMPI ]
      ~> #execute
      ...
    </k>
    <mode>
      NORMAL
    </mode>
    <schedule>
      SHANGHAI
    </schedule>
    <ethereum>
      <evm>
        <callState>
          <program>
            PROGRAM
          </program>
          <jumpDests>
            JUMPDESTS
          </jumpDests>
          <wordStack>
              (S => (S +Int ((N *Int (N +Int 1)) /Int 2)))
            : 0 
            : (N => 0)
            : 287 
            : 2123244496
            : .WordStack
          </wordStack>
          <pc>
            1402
          </pc>
          ...
        </callState>
        ...
      </evm>
      ...
    </ethereum>
    ...
  </kevm>

  requires 0 <Int N
   andBool #rangeUInt(256, S +Int ((N *Int (N +Int 1)) /Int 2))
   andBool #rangeUInt(256, N)
   andBool #rangeUInt(256, S)
   andBool CONDITION ==K bool2Word ( N:Int ==Int 0 )
   andBool PROGRAM ==K #binRuntime(S2KLoopsTest)
   andBool JUMPDESTS ==K #computeValidJumpDests(#binRuntime(S2KLoopsTest))
  [priority(40)]

endmodule
```
The rule matches against the configuration corresponding to the node at the loop entrance and, instead of exploring the iterations one by one, instructs Kontrol to substitute the value of `S` at the top of the stack with `(S +Int ((N *Int (N +Int 1)) /Int 2))`, and `N` — with `0`.

Re-kompile and re-run the proof for the loop invariant to be used:
```
kontrol build --rekompile --require ./invariant_lemmas.k --module-import LoopsTest:SUM-TO-N-INVARIANT
kontrol prove --test LoopsTest.sum_N --use-booster
```

### K6. Verifying `mulWad`

Make `test_wmul_increasing` proof pass by exploring the failing nodes and restricting the values of `a` and `b` or adding missing lemmas.

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract Examples is Test {
    uint256 constant MAX_INT = (2 ** 256) - 1;
    uint constant WAD = 10 ** 18;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / WAD;
    }

    function test_wmul_increasing(uint a, uint b) public {
        uint c = wmul(a, b);
        // overflow check
        assertTrue(a < c && b < c);
    }
}
```
