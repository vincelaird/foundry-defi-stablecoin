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
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();

        console2.log("DSC address:", address(dsc));
        console2.log("Engine address:", address(engine));
        console2.log("HelperConfig address:", address(helperConfig));
        console2.log("WETH address:", weth);
        console2.log("WBTC address:", wbtc);

        // targetContract(address(engine));
        // don't call redeemCollateral unless there is collateral to redeem

        handler = new Handler(engine, dsc);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](18);
        selectors[0] = Handler.depositCollateral.selector;
        selectors[1] = Handler.redeemCollateral.selector;
        selectors[2] = Handler.mintDSC.selector;
        selectors[3] = Handler.getAdditionalFeedPrecision.selector;
        selectors[4] = Handler.getTokenAmountFromUSD.selector;
        selectors[5] = Handler.getAccountCollateralValue.selector;
        selectors[6] = Handler.getUSDValue.selector;
        selectors[7] = Handler.getAccountInformation.selector;
        selectors[8] = Handler.getMinHealthFactor.selector;
        selectors[9] = Handler.getPrecision.selector;
        selectors[10] = Handler.calculateHealthFactor.selector;
        selectors[11] = Handler.getHealthFactor.selector;
        selectors[12] = Handler.getLiquidationBonus.selector;
        selectors[13] = Handler.getCollateralTokenPriceFeed.selector;
        selectors[14] = Handler.getCollateralTokens.selector;
        selectors[15] = Handler.getLiquidationThreshold.selector;
        selectors[16] = Handler.getCollateralBalanceOfUser.selector;
        selectors[17] = Handler.getDSC.selector;
        
        targetSelector(
            FuzzSelector({
                addr: address(handler),
                selectors: selectors
            })
        );
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
        console2.log("times mint was called: ", handler.timesMintWasCalled());

        if (totalSupply > 0 || wethValue > 0 || wbtcValue > 0) {
            assert(wethValue + wbtcValue >= totalSupply);
        }
    }

    function invariant_gettersShouldNotRevert() public view {
        handler.getAdditionalFeedPrecision();
        handler.getTokenAmountFromUSD(0, 1e18);
        handler.getAccountCollateralValue(address(this));
        handler.getUSDValue(0, 1e18);
        handler.getAccountInformation(address(this));
        handler.getMinHealthFactor();
        handler.getPrecision();
        handler.calculateHealthFactor(1e18, 2e18);
        handler.getHealthFactor(address(this));
        handler.getLiquidationBonus();
        handler.getCollateralTokenPriceFeed(0);
        handler.getCollateralTokens();
        handler.getLiquidationThreshold();
        handler.getCollateralBalanceOfUser(address(this), 0);
        handler.getDSC();
    }
}
