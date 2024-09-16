/*
// SPDX-License-Identifier: MIT

// Have our invariant aka properties

// What are our invariants?

// 1. The total supply of DSC should be < the total collateral value
// 2. Getter view functions should never revert

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();

        console2.log("DSC address:", address(dsc));
        console2.log("Engine address:", address(engine));
        console2.log("HelperConfig address:", address(helperConfig));
        console2.log("WETH address:", weth);
        console2.log("WBTC address:", wbtc);

        targetContract(address(engine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get the total supply of DSC
        uint256 totalSupply = dsc.totalSupply();

        // Get the total collateral value
        uint256 totalWETHDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWBTCDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUSDValue(weth, totalWETHDeposited);
        uint256 wbtcValue = engine.getUSDValue(wbtc, totalWBTCDeposited);

        console2.log("weth Value: ", wethValue);
        console2.log("wbtc Value: ", wbtcValue);
        console2.log("totalSupply: ", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
*/