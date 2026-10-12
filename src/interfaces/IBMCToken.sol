// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal interface of the deployed BMC Illuminati token
///         (Ethereum mainnet 0x38224239f2BDae357D47cb864BC533d7f72dF961).
///         Verified on-chain 2026-10-12: name "BMC Illuminati", symbol "BMC", decimals 18,
///         non-proxy bytecode exposing burnFrom(address,uint256) (0x79cc6790) and burn(uint256).
interface IBMCToken {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    /// @dev OpenZeppelin ERC20Burnable semantics: spends the caller's allowance from `account`
    ///      and destroys `amount` tokens, reducing totalSupply. Reverts on insufficient allowance
    ///      or balance.
    function burnFrom(address account, uint256 amount) external;
}
