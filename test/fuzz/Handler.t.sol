// Handler is going to narrow down the way we call functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// Price Feed

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintWasCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(
            engine.getCollateralTokenPriceFeed(address(weth))
        );
    }

    // redeem collateral

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // will cause the same address to be added multiple times
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // breaks invariant
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            depositCollateral(0, 1000e18);
            return;
        }
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine
            .getAccountInformation(sender);
        int256 maxDSCToMint = (int256(collateralValueInUSD) / 2) -
            int256(totalDSCMinted);
        if (maxDSCToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintDSC(amount);
        vm.stopPrank();
        timesMintWasCalled++;
    }

    // Add these functions to your Handler contract

    function getAdditionalFeedPrecision() public view {
        engine.getAdditionalFeedPrecision();
    }

    function getTokenAmountFromUSD(
        uint256 collateralSeed,
        uint256 usdAmountInWEI
    ) public view {
        address collateral = _getCollateralAddressFromSeed(collateralSeed);
        // Bound the amount to prevent overflow
        usdAmountInWEI = bound(usdAmountInWEI, 0, type(uint96).max);
        engine.getTokenAmountFromUSD(collateral, usdAmountInWEI);
    }

    function getAccountCollateralValue(address user) public view {
        engine.getAccountCollateralValue(user);
    }

    function getUSDValue(uint256 collateralSeed, uint256 amount) public view {
        address collateral = _getCollateralAddressFromSeed(collateralSeed);
        // Bound the amount to prevent overflow
        amount = bound(amount, 0, type(uint96).max);
        engine.getUSDValue(collateral, amount);
    }

    function getAccountInformation(address user) public view {
        engine.getAccountInformation(user);
    }

    function getMinHealthFactor() public view {
        engine.getMinHealthFactor();
    }

    function getPrecision() public view {
        engine.getPrecision();
    }

    function calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 collateralValueInUSD
    ) public view {
        totalDSCMinted = bound(totalDSCMinted, 0, type(uint96).max);
        collateralValueInUSD = bound(collateralValueInUSD, 0, type(uint96).max);
        engine.calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function getHealthFactor(address user) public view {
        engine.getHealthFactor(user);
    }

    function getLiquidationBonus() public view {
        engine.getLiquidationBonus();
    }

    function getCollateralTokenPriceFeed(uint256 collateralSeed) public view {
        address collateral = _getCollateralAddressFromSeed(collateralSeed);
        engine.getCollateralTokenPriceFeed(collateral);
    }

    function getCollateralTokens() public view {
        engine.getCollateralTokens();
    }

    function getLiquidationThreshold() public view {
        engine.getLiquidationThreshold();
    }

    function getCollateralBalanceOfUser(
        address user,
        uint256 collateralSeed
    ) public view {
        address collateral = _getCollateralAddressFromSeed(collateralSeed);
        engine.getCollateralBalanceOfUser(user, collateral);
    }

    function getDSC() public view {
        engine.getDSC();
    }

    // helper functions

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function _getCollateralAddressFromSeed(
        uint256 collateralSeed
    ) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return address(weth);
        } else {
            return address(wbtc);
        }
    }
}
