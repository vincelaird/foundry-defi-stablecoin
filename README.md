# Decentralized Stablecoin (DSC)

A decentralized stablecoin system built on Ethereum.

## Features

1. Relative Stability: Pegged to $1.00 USD
   - Utilizes Chainlink Price Feeds for accurate price data
   - Allows exchange of ETH & BTC for DSC

2. Stability Mechanism (Minting): Algorithmic and Decentralized
   - Users can only mint DSC with sufficient collateral

3. Collateral: Exogenous (Crypto)
   - Supported collateral:
     - wETH (Wrapped Ether)
     - wBTC (Wrapped Bitcoin)

## Key Components

- DSCEngine: Core contract managing collateral, minting, and liquidations
- DecentralizedStableCoin: ERC20 token contract for DSC
- HelperConfig: Configuration contract for different network settings

## Testing

Comprehensive unit and fuzz tests are included to ensure the system's robustness:

- `test/unit/DSCEngineTest.t.sol`: Tests for DSCEngine
- `test/unit/DecentralizedStableCoinTest.t.sol`: Tests for DecentralizedStableCoin
- `test/fuzz/Handler.t.sol`: Fuzz tests for DSCEngine
- `test/fuzz/Invariants.t.sol`: Invariant tests for DSCEngine

## Test Coverage

| File                                    | % Lines          | % Statements     | % Branches     | % Funcs         |
|-----------------------------------------|------------------|------------------|----------------|-----------------|
| script/DeployDSC.s.sol                  | 100.00% (11/11)  | 100.00% (14/14)  | 100.00% (0/0)  | 100.00% (1/1)   |
| script/HelperConfig.s.sol               | 85.71% (12/14)   | 88.24% (15/17)   | 66.67% (2/3)   | 66.67% (2/3)    |
| src/DSCEngine.sol                       | 96.77% (90/93)   | 95.41% (104/109) | 63.64% (7/11)  | 100.00% (31/31) |
| src/DecentralizedStableCoin.sol         | 100.00% (9/9)    | 100.00% (13/13)  | 100.00% (4/4)  | 100.00% (3/3)   |
| src/libraries/OracleLib.sol             | 100.00% (7/7)    | 100.00% (7/7)    | 100.00% (1/1)  | 100.00% (1/1)   |
| test/fuzz/Handler.t.sol                 | 98.39% (61/62)   | 97.37% (74/76)   | 87.50% (7/8)   | 100.00% (21/21) |
| test/mocks/FailingTransferFromToken.sol | 100.00% (2/2)    | 100.00% (2/2)    | 100.00% (0/0)  | 100.00% (1/1)   |
| test/mocks/MockV3Aggregator.sol         | 100.00% (14/14)  | 100.00% (15/15)  | 100.00% (0/0)  | 100.00% (4/4)   |
| Total                                   | 97.17% (206/212) | 96.44% (244/253) | 77.78% (21/27) | 98.46% (64/65)  |

## Smart Contract Audit Preparation

1. Proper Oracle Usage
   - Implemented fail-safes for price feed issues
   - Staleness checks for price data

2. Extensive Test Coverage
   - Unit tests for all core functions
   - Fuzz tests for invariant checking

3. Key Invariants
   - Protocol must always be overcollateralized
   - User health factors are accurately calculated and enforced

## Setup and Deployment

1. Clone the repository
2. Install dependencies: `forge install`
3. Run tests: `forge test`
4. Deploy: `forge script script/DeployDSC.s.sol:DeployDSC --rpc-url $RPC_URL --account $ACCOUNT`

## License

This project is licensed under the MIT License.
