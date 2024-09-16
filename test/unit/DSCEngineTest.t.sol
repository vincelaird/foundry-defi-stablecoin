// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {FailingTransferFromToken} from "../../test/mocks/FailingTransferFromToken.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    uint256 deployerKey;

    uint256 amountToMint = 100 ether;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; // may need to make this not be a constant
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        // if (block.chainid == 31_337) {
        //     vm.deal(USER, STARTING_ERC20_BALANCE);
        // }
    }

    // Constructor Tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsMustBeSame
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // Price Tests
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30000e18;

        uint256 actualUsd = engine.getUSDValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    // Deposit Collateral Tests
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting()
        public
        depositedCollateral
    {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine
            .getAccountInformation(USER);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUSD(
            weth,
            collateralValueInUSD
        );
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertsIfMintedDSCBreaksHealthFactor() public {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL *
                (uint256(price) * engine.getAdditionalFeedPrecision())) /
            engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(
            engine.getUSDValue(weth, AMOUNT_COLLATERAL),
            amountToMint
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral()
        public
        depositedCollateralAndMintedDSC
    {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    // mintDsc Tests

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL *
                (uint256(price) * engine.getAdditionalFeedPrecision())) /
            engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = engine.calculateHealthFactor(
            engine.getUSDValue(weth, AMOUNT_COLLATERAL),
            amountToMint
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        engine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDSC() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 amountToMintForTest = 5 ether; // Changed from 100 ether to 5 ether
        engine.mintDSC(amountToMintForTest);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMintForTest);
    }

    // burnDSC Tests

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testCannotBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDSC(1);
    }

    function testCanBurnDSC() public depositedCollateralAndMintedDSC {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        engine.burnDSC(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    // redeemCollateral Tests

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // redeemCollateralForDSC Tests

    function testMustRedeemMoreThanZero()
        public
        depositedCollateralAndMintedDSC
    {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateralForDSC(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        dsc.approve(address(engine), amountToMint);
        engine.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    // healthFactor Tests

    function testProperlyReportsHealthFactor()
        public
        depositedCollateralAndMintedDSC
    {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collateral at all times
        // 20,000 * 50% = $10,000
        // $10,000 / $100 = 100
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne()
        public
        depositedCollateralAndMintedDSC
    {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $150 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = engine.getHealthFactor(USER);
        // $180 collateral / $200 debt = 0.9
        assertEq(userHealthFactor, 0.9 ether);
    }

    // Liquidation Tests

    function testCannotLiquidateGoodHealthFactor()
        public
        depositedCollateralAndMintedDSC
    {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDSC(
            weth,
            collateralToCover,
            amountToMint
        );
        dsc.approve(address(engine), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBroken.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDSC(
            weth,
            collateralToCover,
            amountToMint
        );
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint); // we are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = engine.getTokenAmountFromUSD(
            weth,
            amountToMint
        ) +
            (engine.getTokenAmountFromUSD(weth, amountToMint) /
                engine.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Determine how much WETH the user lost
        uint256 amountLiquidated = engine.getTokenAmountFromUSD(
            weth,
            amountToMint
        ) +
            (engine.getTokenAmountFromUSD(weth, amountToMint) /
                engine.getLiquidationBonus());
        uint256 usdAmountLiquidated = engine.getUSDValue(
            weth,
            amountLiquidated
        );
        uint256 expectedUserCollateralValueInUSD = engine.getUSDValue(
            weth,
            AMOUNT_COLLATERAL
        ) - usdAmountLiquidated;
        (, uint256 userCollateralValueInUSD) = engine.getAccountInformation(
            USER
        );
        uint256 hardCodedExpectedValue = 70000000000000000020;
        assertEq(userCollateralValueInUSD, expectedUserCollateralValueInUSD);
        assertEq(userCollateralValueInUSD, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDSCMinted, ) = engine.getAccountInformation(
            liquidator
        );
        assertEq(liquidatorDSCMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDSCMinted, ) = engine.getAccountInformation(USER);
        assertEq(userDSCMinted, 0);
    }

    // View & Pure Function Tests

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = engine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = engine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation()
        public
        depositedCollateral
    {
        (, uint256 collateralValue) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValue = engine.getUSDValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = engine.getCollateralBalanceOfUser(
            USER,
            weth
        );
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = engine.getUSDValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDSC() public view {
        address dscAddress = engine.getDSC();
        assertEq(dscAddress, address(dsc));
    }

    function testGetSepoliaEthConfig() public {
        // skip test if no private key is provided
        if (vm.envUint("PRIVATE_KEY") == 0) {
            return;
        }
        vm.chainId(11155111); // Sepolia chain ID
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address wethAddress,
            address wbtcAddress,
            uint256 deployerKeyForSepolia // untested, need deployer key for this
        ) = helperConfig.activeNetworkConfig();

        assertEq(wethAddress, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81);
        assertEq(wbtcAddress, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        assertEq(wethUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        assertEq(wbtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
        // assertEq(
        //     deployerKeyForSepolia,
        //     0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        // );
    }

    function testAnvilConfigReuse() public {
        vm.chainId(31337); // Set to Anvil chain ID
        HelperConfig helperConfig = new HelperConfig();

        HelperConfig.NetworkConfig memory config1 = helperConfig
            .getOrCreateAnvilEthConfig();
        HelperConfig.NetworkConfig memory config2 = helperConfig
            .getOrCreateAnvilEthConfig();

        // Assert that the addresses in both configs are the same
        assertEq(config1.wethUsdPriceFeed, config2.wethUsdPriceFeed);
        assertEq(config1.wbtcUsdPriceFeed, config2.wbtcUsdPriceFeed);
        assertEq(config1.weth, config2.weth);
        assertEq(config1.wbtc, config2.wbtc);
        assertEq(config1.deployerKey, config2.deployerKey);
    }

    function testLiquidationWithZeroDebtToCover() public {
        uint256 collateralToCoverForZeroDebtTest = 1 ether;

        ERC20Mock(weth).mint(liquidator, collateralToCoverForZeroDebtTest);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(
            address(engine),
            collateralToCoverForZeroDebtTest
        );
        engine.depositCollateralAndMintDSC(
            weth,
            collateralToCoverForZeroDebtTest,
            amountToMint / 2
        );
        vm.stopPrank();

        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralForDSCWithInvalidAmount() public {
        // Setup: Deploy contracts, deposit collateral, mint DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        // Attempt to redeem all collateral for slightly less than minted DSC
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0
            )
        );
        engine.redeemCollateralForDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint - 1
        );
        vm.stopPrank();
    }

    function testStaleCheckReverts() public {
        console2.log("Starting testStaleCheckReverts");

        // Setup: Deploy contracts, mock price feed, etc.
        MockV3Aggregator mockAggregator = new MockV3Aggregator(
            8, // decimals
            2000e8 // initial answer
        );
        console2.log("MockV3Aggregator deployed at:", address(mockAggregator));

        // Set the current block timestamp to a future time
        vm.warp(block.timestamp + 1 days);
        uint256 currentTimestamp = block.timestamp;

        // Set the mock price feed to return a timestamp older than the staleness threshold
        uint256 oldTimestamp = currentTimestamp - 4 hours;
        console2.log("Current timestamp:", currentTimestamp);
        console2.log("Old timestamp:", oldTimestamp);

        mockAggregator.updateRoundData(
            0, // roundId
            5000e8, // answer
            oldTimestamp,
            oldTimestamp
        );
        console2.log("MockV3Aggregator updated at:", oldTimestamp);
        // Replace the existing price feed with our mock
        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = weth;
        priceFeeds[0] = address(mockAggregator);
        DSCEngine newEngine = new DSCEngine(tokens, priceFeeds, address(dsc));

        // Log values before calling getUSDValue
        console2.log("WETH address:", weth);
        console2.log("Current timestamp:", block.timestamp);
        console2.log("Old timestamp:", oldTimestamp);

        // Expect revert with the correct error
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);

        // Call a function that uses the price feed
        newEngine.getUSDValue(weth, 1e18);
    }

    function testConstructorMismatchedLengths() public {
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = wbtc;

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = ethUsdPriceFeed;

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsMustBeSame
                .selector
        );
        new DSCEngine(tokens, priceFeeds, address(dsc));
    }

    function testDepositCollateralInvalidToken() public {
        ERC20Mock invalidToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(invalidToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMintDscBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );

        uint256 maxDscToMint = engine.getUSDValue(weth, AMOUNT_COLLATERAL) / 2; // 50% collateralization
        uint256 tooMuchDsc = maxDscToMint + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                990099009900990099
            )
        );
        engine.mintDSC(tooMuchDsc);
        vm.stopPrank();
    }

    function testBurnMoreDscThanUserHas()
        public
        depositedCollateralAndMintedDSC
    {
        vm.startPrank(USER);
        uint256 tooMuchDsc = amountToMint + 1;
        vm.expectRevert();
        engine.burnDSC(tooMuchDsc);
        vm.stopPrank();
    }

    function testLiquidateMoreDebtThanUserHas() public {
        // Setup: USER deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        // Reduce the price of ETH to make USER's position liquidatable
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); // 1 ETH = $1000

        // Setup: Liquidator mints DSC
        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );

        // Attempt to liquidate more than the user's debt
        uint256 tooMuchDebt = amountToMint + 1;
        vm.expectRevert();
        engine.liquidate(weth, USER, tooMuchDebt);
        vm.stopPrank();
    }

    function testLiquidationDoesntImproveHealthFactor() public {
        // Setup: USER deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        // Reduce the price of ETH to make USER's position liquidatable
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); // 1 ETH = $1000

        // Setup: Liquidator mints DSC
        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );

        // Attempt to liquidate with a very small amount (health factor is not broken)
        uint256 verySmallDebt = 1;
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBroken.selector);
        engine.liquidate(weth, USER, verySmallDebt);
        vm.stopPrank();
    }

    function testAttemptLiquidationWhenHealthFactorIsNotBroken() public {
        // Setup: USER deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        // Setup: Liquidator mints DSC
        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        // Attempt to liquidate when health factor is not broken
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBroken.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    function testDepositCollateralWithZeroAmount() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), 0);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testMintDSCWithZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRedeemCollateralWithZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralForDSCWithZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateralForDSC(weth, 0, 0);
        vm.stopPrank();
    }

    function testBurnDSCWithZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testDepositCollateralFailedTransfer() public {
        FailingTransferFromToken failingToken = new FailingTransferFromToken();

        address[] memory newTokens = new address[](1);
        newTokens[0] = address(failingToken);
        address[] memory newPriceFeeds = new address[](1);
        newPriceFeeds[0] = ethUsdPriceFeed;

        DSCEngine newEngine = new DSCEngine(
            newTokens,
            newPriceFeeds,
            address(dsc)
        );

        failingToken.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        failingToken.approve(address(newEngine), AMOUNT_COLLATERAL);

        // Directly test the transferFrom function
        bool transferResult = failingToken.transferFrom(
            USER,
            address(newEngine),
            AMOUNT_COLLATERAL
        );
        assertFalse(transferResult);
        assertTrue(failingToken.transferFromCalled());

        // Verify that the transfer didn't occur
        assertEq(failingToken.balanceOf(USER), AMOUNT_COLLATERAL);
        assertEq(failingToken.balanceOf(address(newEngine)), 0);

        // Test the depositCollateral function, which should revert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        newEngine.depositCollateral(address(failingToken), AMOUNT_COLLATERAL);
        vm.stopPrank();

        // Verify again that the balances haven't changed
        assertEq(failingToken.balanceOf(USER), AMOUNT_COLLATERAL);
        assertEq(failingToken.balanceOf(address(newEngine)), 0);
    }

    // How do we adjust our invariant tests for this?
    // function testInvariantBreaks() public depositedCollateralAndMintedDSC {
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);

    //     uint256 totalSupply = dsc.totalSupply();
    //     uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(engine));
    //     uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(engine));

    //     uint256 wethValue = engine.getUSDValue(weth, wethDeposited);
    //     uint256 wbtcValue = engine.getUSDValue(wbtc, wbtcDeposited);

    //     console2.log("wethValue: %s", wethValue);
    //     console2.log("wbtcValue: %s", wbtcValue);
    //     console2.log("totalSupply: %s", totalSupply);

    //     assert(wethValue + wbtcValue >= totalSupply);
    // }
}
