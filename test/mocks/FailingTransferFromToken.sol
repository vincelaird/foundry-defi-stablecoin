// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract FailingTransferFromToken is ERC20Mock {
    bool public transferFromCalled;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        transferFromCalled = true;
        return false;
    }
}
