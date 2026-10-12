// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title StandardArt
/// @notice Fully on-chain SVG renderer for the 423 Standard BMC Illuminati Pass NFTs.
/// @dev Every function is `internal` so the compiler inlines the library into the caller and no
///      link placeholders are left in the bytecode.
///
///      Trait space: 6 backgrounds x 5 cloaks x 6 eyes x 5 symbols x 6 accessories = 5400 combos.
///      Artwork id `n` (1..423) is mapped to combination `(n - 1) * 1327 + 777 mod 5400`.
///      1327 is coprime with 5400 (= 2^3 * 3^3 * 5^2), so the map is a bijection on [0, 5400) and
///      423 distinct ids always yield 423 distinct combinations.
///
///      Standard art never contains the Genesis-exclusive traits: no golden third eye, no floating
///      golden eye-in-triangle and no golden cloak. Cloak colours are black, charcoal, navy, wine and
///      moss; symbols are silver.
library StandardArt {
    using Strings for uint256;

    uint256 internal constant COMBOS = 5400;
    uint256 internal constant STRIDE = 1327;
    uint256 internal constant OFFSET = 777;

    struct Traits {
        uint8 background;
        uint8 cloak;
        uint8 eyes;
        uint8 symbol;
        uint8 accessory;
    }

    /// @notice Decode the trait combination for a Standard artwork id (1..423).
    function traitsOf(uint256 artworkId) internal pure returns (Traits memory t) {
        require(artworkId >= 1 && artworkId <= 423, "StandardArt: bad id");
        uint256 c = ((artworkId - 1) * STRIDE + OFFSET) % COMBOS;
        t.background = uint8(c % 6);
        c /= 6;
        t.cloak = uint8(c % 5);
        c /= 5;
        t.eyes = uint8(c % 6);
        c /= 6;
        t.symbol = uint8(c % 5);
        c /= 5;
        t.accessory = uint8(c % 6);
    }

    /// @notice Packed combination index, useful for uniqueness checks.
    function comboIndex(uint256 artworkId) internal pure returns (uint256) {
        require(artworkId >= 1 && artworkId <= 423, "StandardArt: bad id");
        return ((artworkId - 1) * STRIDE + OFFSET) % COMBOS;
    }

    // ---------------------------------------------------------------------------------------------
    // Trait names
    // ---------------------------------------------------------------------------------------------

    function backgroundName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Midnight";
        if (i == 1) return "Deep Violet";
        if (i == 2) return "Forest Shade";
        if (i == 3) return "Crimson Dusk";
        if (i == 4) return "Abyss Blue";
        return "Ashen Fog";
    }

    function cloakName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Shadow Black";
        if (i == 1) return "Charcoal";
        if (i == 2) return "Navy";
        if (i == 3) return "Wine";
        return "Moss";
    }

    function eyesName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Calm";
        if (i == 1) return "Red Glare";
        if (i == 2) return "Sleepy";
        if (i == 3) return "Wide Awake";
        if (i == 4) return "Cyan Stare";
        return "Violet Gaze";
    }

    function symbolName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Silver Crescent";
        if (i == 1) return "Silver Pentagon";
        if (i == 2) return "Silver Spiral";
        if (i == 3) return "Silver Cross";
        return "Silver Diamond";
    }

    function accessoryName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "None";
        if (i == 1) return "Silver Chain";
        if (i == 2) return "Hoop Earring";
        if (i == 3) return "Cigar";
        if (i == 4) return "Monocle";
        return "Scar";
    }

    // ---------------------------------------------------------------------------------------------
    // SVG
    // ---------------------------------------------------------------------------------------------

    function backgroundColors(uint8 i) private pure returns (string memory a, string memory b) {
        if (i == 0) return ("#0b0b14", "#1a1a2e");
        if (i == 1) return ("#1b0a2e", "#3a1b5c");
        if (i == 2) return ("#07170f", "#163b26");
        if (i == 3) return ("#2a070c", "#5a1420");
        if (i == 4) return ("#05121f", "#0e2f4f");
        return ("#171717", "#3a3a3a");
    }

    function cloakColors(uint8 i) private pure returns (string memory fill, string memory edge) {
        if (i == 0) return ("#0d0d0d", "#2b2b2b");
        if (i == 1) return ("#2a2a2e", "#4a4a52");
        if (i == 2) return ("#101c3a", "#24376a");
        if (i == 3) return ("#3a0d1c", "#6a1d36");
        return ("#17301a", "#2c5a30");
    }

    function eyesSvg(uint8 i) private pure returns (string memory) {
        if (i == 0) {
            return "<ellipse cx='160' cy='215' rx='22' ry='24' fill='#f4f4f4'/><ellipse cx='240' cy='215' rx='22' ry='24' fill='#f4f4f4'/><circle cx='164' cy='218' r='9' fill='#111'/><circle cx='244' cy='218' r='9' fill='#111'/>";
        }
        if (i == 1) {
            return "<ellipse cx='160' cy='215' rx='22' ry='18' fill='#ff2d2d'/><ellipse cx='240' cy='215' rx='22' ry='18' fill='#ff2d2d'/><rect x='156' y='204' width='8' height='22' fill='#111'/><rect x='236' y='204' width='8' height='22' fill='#111'/>";
        }
        if (i == 2) {
            return "<path d='M138 220 q22 -18 44 0 v10 q-22 -10 -44 0z' fill='#f4f4f4'/><path d='M218 220 q22 -18 44 0 v10 q-22 -10 -44 0z' fill='#f4f4f4'/><circle cx='160' cy='222' r='6' fill='#111'/><circle cx='240' cy='222' r='6' fill='#111'/>";
        }
        if (i == 3) {
            return "<circle cx='160' cy='215' r='28' fill='#f4f4f4'/><circle cx='240' cy='215' r='28' fill='#f4f4f4'/><circle cx='160' cy='215' r='13' fill='#111'/><circle cx='240' cy='215' r='13' fill='#111'/><circle cx='154' cy='208' r='4' fill='#fff'/><circle cx='234' cy='208' r='4' fill='#fff'/>";
        }
        if (i == 4) {
            return "<ellipse cx='160' cy='215' rx='22' ry='20' fill='#36f0ff'/><ellipse cx='240' cy='215' rx='22' ry='20' fill='#36f0ff'/><circle cx='160' cy='215' r='8' fill='#06303a'/><circle cx='240' cy='215' r='8' fill='#06303a'/>";
        }
        return "<ellipse cx='160' cy='215' rx='22' ry='20' fill='#b56cff'/><ellipse cx='240' cy='215' rx='22' ry='20' fill='#b56cff'/><circle cx='160' cy='215' r='8' fill='#2a0a44'/><circle cx='240' cy='215' r='8' fill='#2a0a44'/>";
    }

    function symbolSvg(uint8 i) private pure returns (string memory) {
        if (i == 0) {
            return "<path d='M200 300 a22 22 0 1 0 0 44 a16 16 0 1 1 0 -44z' fill='#cfcfcf'/>";
        }
        if (i == 1) {
            return
                "<polygon points='200,300 221,315 213,340 187,340 179,315' fill='none' stroke='#cfcfcf' stroke-width='4'/>";
        }
        if (i == 2) {
            return "<path d='M200 322 m-2 0 a2 2 0 0 1 4 0 a6 6 0 0 1 -12 0 a10 10 0 0 1 20 0 a14 14 0 0 1 -28 0 a18 18 0 0 1 36 0' fill='none' stroke='#cfcfcf' stroke-width='3'/>";
        }
        if (i == 3) {
            return "<rect x='196' y='300' width='8' height='44' fill='#cfcfcf'/><rect x='182' y='312' width='36' height='8' fill='#cfcfcf'/>";
        }
        return "<polygon points='200,298 220,322 200,346 180,322' fill='none' stroke='#cfcfcf' stroke-width='4'/>";
    }

    function accessorySvg(uint8 i) private pure returns (string memory) {
        if (i == 0) return "";
        if (i == 1) {
            return
                "<path d='M150 285 q50 30 100 0' fill='none' stroke='#d8d8d8' stroke-width='5' stroke-dasharray='6 4'/>";
        }
        if (i == 2) return "<circle cx='118' cy='236' r='9' fill='none' stroke='#d8d8d8' stroke-width='3'/>";
        if (i == 3) {
            return "<rect x='222' y='262' width='48' height='10' rx='3' fill='#6b4a2b'/><circle cx='272' cy='267' r='5' fill='#ff7a1a'/>";
        }
        if (i == 4) {
            return "<circle cx='240' cy='215' r='31' fill='none' stroke='#d8d8d8' stroke-width='3'/><line x1='268' y1='228' x2='292' y2='270' stroke='#d8d8d8' stroke-width='2'/>";
        }
        return "<line x1='135' y1='190' x2='150' y2='245' stroke='#7d3a3a' stroke-width='4'/><line x1='136' y1='205' x2='146' y2='203' stroke='#7d3a3a' stroke-width='3'/><line x1='141' y1='222' x2='151' y2='220' stroke='#7d3a3a' stroke-width='3'/>";
    }

    /// @notice Render the complete SVG for a Standard artwork id.
    function render(uint256 artworkId) internal pure returns (string memory) {
        Traits memory t = traitsOf(artworkId);
        return string.concat(
            _backdrop(t.background),
            _cloak(t.cloak),
            "<ellipse cx='200' cy='235' rx='78' ry='62' fill='#3f8f4a'/><path d='M150 268 q50 34 100 0' fill='none' stroke='#1d4a24' stroke-width='5' stroke-linecap='round'/><ellipse cx='160' cy='192' rx='26' ry='22' fill='#3f8f4a'/><ellipse cx='240' cy='192' rx='26' ry='22' fill='#3f8f4a'/>",
            eyesSvg(t.eyes),
            symbolSvg(t.symbol),
            accessorySvg(t.accessory),
            _footer(artworkId)
        );
    }

    function _backdrop(uint8 bg) private pure returns (string memory) {
        (string memory bgA, string memory bgB) = backgroundColors(bg);
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400' width='400' height='400'><defs><radialGradient id='g' cx='50%' cy='40%' r='70%'><stop offset='0%' stop-color='",
            bgB,
            "'/><stop offset='100%' stop-color='",
            bgA,
            "'/></radialGradient></defs><rect width='400' height='400' fill='url(#g)'/>"
        );
    }

    function _cloak(uint8 cloak) private pure returns (string memory) {
        (string memory cFill, string memory cEdge) = cloakColors(cloak);
        return string.concat(
            "<path d='M70 390 L95 170 Q200 40 305 170 L330 390z' fill='",
            cFill,
            "' stroke='",
            cEdge,
            "' stroke-width='6'/><path d='M118 390 L130 200 Q200 120 270 200 L282 390z' fill='#070707' opacity='0.85'/>"
        );
    }

    function _footer(uint256 artworkId) private pure returns (string memory) {
        return string.concat(
            "<text x='200' y='385' font-family='monospace' font-size='12' fill='#9a9a9a' text-anchor='middle'>BMC ILLUMINATI PASS / STANDARD #",
            artworkId.toString(),
            "</text></svg>"
        );
    }

    /// @notice JSON attribute fragments for the visual traits (no leading comma).
    function attributesJson(uint256 artworkId) internal pure returns (string memory) {
        Traits memory t = traitsOf(artworkId);
        return string.concat(
            '{"trait_type":"Background","value":"',
            backgroundName(t.background),
            '"},{"trait_type":"Cloak","value":"',
            cloakName(t.cloak),
            '"},{"trait_type":"Eyes","value":"',
            eyesName(t.eyes),
            '"},{"trait_type":"Symbol","value":"',
            symbolName(t.symbol),
            '"},{"trait_type":"Accessory","value":"',
            accessoryName(t.accessory),
            '"}'
        );
    }
}
