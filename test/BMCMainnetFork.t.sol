
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";

interface IRealBMC {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract BMCMainnetForkTest is Test {
    address constant BMC =
        0x38224239f2BDae357D47cb864BC533d7f72dF961;

    address constant VRF =
        0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;

    uint256 constant PRICE = 1_000_000e18;

    address buyer = address(0xBEEF);

    function test_RealBMCGenesisMint() public {
        require(block.chainid == 1, "Ethereum mainnet fork required");
        require(BMC.code.length > 0, "BMC contract missing");
        require(VRF.code.length > 0, "VRF coordinator missing");

        IRealBMC token = IRealBMC(BMC);
        assertEq(token.decimals(), 18);

        BMCIlluminatiPass pass =
            new BMCIlluminatiPass(address(this), BMC, VRF);

        pass.setGenesisImagesCID(
            "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u"
        );

        // Test-only balance adjustment on the local fork.
        deal(BMC, buyer, PRICE, true);

        assertEq(token.balanceOf(buyer), PRICE);

        uint256 supplyBefore = token.totalSupply();

        vm.startPrank(buyer);
        token.approve(address(pass), PRICE);
        uint256 tokenId = pass.mintGenesis();
        vm.stopPrank();

        assertEq(tokenId, 1);
        assertEq(pass.ownerOf(1), buyer);
        assertEq(pass.totalBurned(), PRICE);
        assertEq(token.balanceOf(buyer), 0);
        assertEq(token.totalSupply(), supplyBefore - PRICE);
    }
}
