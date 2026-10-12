// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @dev Mirrors the deployed BMC token behaviour relevant to the pass: 18 decimals and
///      OpenZeppelin ERC20Burnable.burnFrom (spend allowance, then burn).
contract MockBMC is ERC20, ERC20Burnable {
    constructor() ERC20("BMC Illuminati", "BMC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev A token whose burnFrom moves tokens to a sink instead of destroying them.
contract FakeBurnBMC is ERC20 {
    constructor() ERC20("Fake BMC", "FBMC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _transfer(account, address(0xdead), amount);
    }
}

/// @dev A token with 6 decimals to exercise the decimals guard.
contract SixDecimalBMC is ERC20, ERC20Burnable {
    constructor() ERC20("Six", "SIX") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
