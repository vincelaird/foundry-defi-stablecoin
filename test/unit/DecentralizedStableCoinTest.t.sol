// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address public USER = makeAddr("user");
    address public owner;

    function setUp() public {
        owner = address(this);
        dsc = new DecentralizedStableCoin();
        dsc.transferOwnership(owner);
    }

    function testMint() public {
        dsc.mint(USER, 10 ether);
        assertEq(dsc.balanceOf(USER), 10 ether);
    }

    function testBurn() public {
        dsc.mint(USER, 10 ether);
        vm.prank(USER);
        dsc.burn(10 ether);
        assertEq(dsc.balanceOf(USER), 0);
    }

    function testMintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 100);
    }

    function testMintZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(USER, 0);
    }

    function testBurnFromZeroAddress() public {
        vm.prank(address(0));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(100);
    }

    function testBurnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }
}
