// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IBMCToken} from "./interfaces/IBMCToken.sol";
import {StandardArt} from "./StandardArt.sol";
import {MysteryDraw} from "./MysteryDraw.sol";

/// @title BMC Illuminati Pass
/// @notice 500-piece ERC-721 collection minted by permanently burning BMC through `burnFrom`.
///
///  Phase 1 (token ids 1-40): sequential Genesis mints at 1,000,000 BMC each. Token #1 is the
///  Legendary Genesis. Token id N receives artwork genesis-NN.png for N in 1..40.
///
///  Phase 2 (token ids 41-500): up to 460 mystery mints at 350,000 BMC each. A mystery mint burns BMC
///  and mints a pending-reveal NFT. No randomness is requested per mint.
///
///  Single seed. Once the sale is closed (sold out, or `SALE_IDLE_TIMEOUT` without a mint once at
///  least one mystery token exists), anyone may request ONE Chainlink VRF v2.5 random word. The first word the
///  coordinator delivers for any request this contract made becomes the seed; every later delivery
///  is ignored. All mystery outcomes are a pure function of the seed (`MysteryDraw`): token 41 + i is
///  step i of a Fisher-Yates draw without replacement over 37 Genesis (genesis-41 .. genesis-77) and
///  423 Standard (on-chain SVG) outcomes. Metadata is final in the same transaction that stores the
///  seed; `finalizeReveals` only materializes outcomes into storage and emits `Revealed` events.
///
///  Recovery. If a request is not fulfilled within `SEED_REQUEST_TIMEOUT` (Chainlink drops underfunded
///  requests after 24 hours), anyone may request again, from the configured subscription or from any
///  subscription that lists this contract as a consumer, on any gas lane the coordinator has a proving
///  key for. The timeout is tracked per subscription: a request charged to one subscription never
///  delays a request charged to another, so a stranger's unfunded subscription cannot hold the
///  configured one back. There is no reroll: a delivery after the seed is set changes nothing, and
///  nothing lets the owner, a minter or a keeper choose, replace or preview the seed.
///
///  Trust model: the owner has no on-chain power beyond the `Ownable` role itself (useful for
///  marketplace collection pages). The images CID, VRF coordinator, subscription id, gas lane and
///  request parameters are fixed at construction. The VRF subscription is administered on the
///  coordinator by its own owner (adding this contract as consumer, funding it with ETH).
contract BMCIlluminatiPass is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ------------------------------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------------------------------

    enum Tier {
        Pending, // 0: mystery mint awaiting the seed
        LegendaryGenesis, // 1: token #1
        Genesis, // 2
        Standard // 3
    }

    enum RevealStatus {
        None, // not a mystery token / not minted
        AwaitingRandomness, // seed not delivered yet
        RandomnessStored, // seed delivered: outcome and metadata are final, not yet materialized
        Revealed // outcome materialized in storage (`Revealed` event emitted)
    }

    // ------------------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------------------

    uint256 public constant MAX_SUPPLY = 500;
    uint256 public constant GENESIS_PHASE_SUPPLY = 40;
    uint256 public constant MYSTERY_SUPPLY = 460;
    uint256 public constant TOTAL_GENESIS = 77;
    uint256 public constant MYSTERY_GENESIS = 37;
    uint256 public constant TOTAL_STANDARD = 423;

    /// @dev BMC has 18 decimals (verified on mainnet; also re-checked on every mint).
    uint8 public constant BMC_DECIMALS = 18;
    uint256 public constant GENESIS_PRICE = 1_000_000 * 1e18;
    uint256 public constant MYSTERY_PRICE = 350_000 * 1e18;
    /// @dev 40 * 1,000,000 + 460 * 350,000 = 201,000,000 BMC.
    uint256 public constant MAX_TOTAL_BURN = 201_000_000 * 1e18;

    /// @notice IPFS directory holding genesis-01.png .. genesis-77.png (CIDv1, verified against
    ///         `artwork/genesis/` through a public gateway on 2026-10-12).
    string public constant GENESIS_IMAGES_CID = "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    /// @notice Once at least one mystery token exists, the sale closes after this long without any
    ///         mint. The clock starts at the first mystery mint, not at the 40th Genesis mint, so a
    ///         quiet period between the phases cannot end the sale with nothing to reveal.
    uint256 public constant SALE_IDLE_TIMEOUT = 30 days;
    /// @notice A seed request that is still unfulfilled after this long may be re-requested by anyone
    ///         from the same subscription. Longer than Chainlink's 24-hour pending window, so an honest
    ///         node has dropped the old request before a new one is opened.
    uint256 public constant SEED_REQUEST_TIMEOUT = 36 hours;

    /// @dev Chainlink VRF v2.5, Ethereum mainnet: 500 gwei gas lane. Verified on 2026-10-12 against
    ///      coordinator 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a: s_provingKeyHashes(2) returns this
    ///      hash and s_provingKeys(hash) returns (exists = true, maxGas = 500 gwei).
    bytes32 public constant KEY_HASH = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b;
    uint32 public constant CALLBACK_GAS_LIMIT = 500_000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    bool public constant NATIVE_PAYMENT = true;

    IBMCToken public immutable BMC;
    IVRFCoordinatorV2Plus public immutable VRF_COORDINATOR;
    /// @notice Chainlink VRF v2.5 subscription paying (in ETH) for the seed request.
    uint256 public immutable SUBSCRIPTION_ID;

    // ------------------------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------------------------

    /// @notice Number of NFTs minted so far (also the last token id).
    uint256 public totalMinted;
    /// @notice Total BMC (18-decimal units) burned through this contract.
    uint256 public totalBurned;
    /// @notice Number of mystery tokens whose outcome has been materialized in storage.
    uint256 public revealedCount;
    /// @notice Number of Genesis outcomes materialized from the mystery pool so far.
    uint256 public mysteryGenesisRevealed;
    /// @notice Timestamp of the last mint of either phase.
    uint64 public lastMintAt;

    /// @notice Timestamp of the latest seed request charged to each subscription (0 if none yet). The
    ///         re-request timeout is enforced per subscription, so no subscription can block another.
    mapping(uint256 subscriptionId => uint64) public lastSeedRequestAtOf;
    /// @notice Number of seed requests made so far, all subscriptions included (1 on the happy path).
    uint32 public seedRequestCount;
    /// @notice True once the seed is set.
    bool public seedSet;
    /// @notice The VRF word every mystery outcome derives from (meaningful only when `seedSet`).
    uint256 public seed;
    /// @notice The request whose word became the seed.
    uint256 public seedRequestId;
    /// @notice Requests made by this contract (any of them may deliver the seed; first delivery wins).
    mapping(uint256 requestId => bool) public isSeedRequest;

    mapping(uint256 tokenId => Tier) private _tier;
    mapping(uint256 tokenId => uint16) private _artworkId;

    /// @dev Virtual Fisher-Yates over 460 slots for materialization. slot(i) = i unless swapped;
    ///      stores value + 1. Mirrors `MysteryDraw.slotAt` step by step.
    mapping(uint256 => uint256) private _slotSwap;

    // ------------------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------------------

    event GenesisMinted(address indexed minter, uint256 indexed tokenId, uint16 artworkId, uint256 bmcBurned);
    event MysteryMinted(address indexed minter, uint256 indexed tokenId, uint256 bmcBurned);
    event SeedRequested(uint256 indexed requestId, uint32 attempt, uint256 subscriptionId, bytes32 keyHash);
    event SeedDelivered(uint256 indexed requestId, uint256 seed);
    event SeedDeliveryIgnored(uint256 indexed requestId, uint256 randomWord);
    event Revealed(uint256 indexed tokenId, Tier tier, uint16 artworkId);

    // ------------------------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------------------------

    error GenesisPhaseOver();
    error GenesisPhaseNotOver();
    error SoldOut();
    error SaleIsClosed();
    error SaleNotClosed();
    error SeedAlreadyDelivered();
    error SeedRequestPending(uint256 retryAt);
    error KeyHashNotRegistered(bytes32 keyHash);
    error DefaultLaneStillRegistered(bytes32 keyHash);
    error UnexpectedTokenDecimals(uint8 actual);
    error BurnMismatch(uint256 expected, uint256 actual);
    error OnlyCoordinator();
    error UnknownRequest(uint256 requestId);
    error NoRandomWords();
    error NonexistentToken(uint256 tokenId);

    // ------------------------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------------------------

    /// @param initialOwner Collection owner. Has no on-chain power beyond the role itself.
    /// @param bmcToken The BMC token (mainnet 0x38224239f2BDae357D47cb864BC533d7f72dF961).
    /// @param vrfCoordinator Chainlink VRF v2.5 coordinator (mainnet 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a).
    /// @param subscriptionId VRF v2.5 subscription this contract must be a consumer of, funded with ETH.
    /// @dev Makes no external call: the launch rehearses constructors on an empty chain. Token and
    ///      coordinator behaviour is checked on first use instead.
    constructor(address initialOwner, address bmcToken, address vrfCoordinator, uint256 subscriptionId)
        ERC721("BMC Illuminati Pass", "BMCPASS")
        Ownable(initialOwner)
    {
        require(bmcToken != address(0) && vrfCoordinator != address(0) && subscriptionId != 0, "zero argument");
        BMC = IBMCToken(bmcToken);
        VRF_COORDINATOR = IVRFCoordinatorV2Plus(vrfCoordinator);
        SUBSCRIPTION_ID = subscriptionId;
    }

    // ------------------------------------------------------------------------------------------
    // Minting
    // ------------------------------------------------------------------------------------------

    /// @notice Phase 1: mint the next sequential Genesis NFT (ids 1-40) for 1,000,000 BMC.
    function mintGenesis() external nonReentrant returns (uint256 tokenId) {
        if (totalMinted >= GENESIS_PHASE_SUPPLY) revert GenesisPhaseOver();

        _burnExact(msg.sender, GENESIS_PRICE);

        tokenId = ++totalMinted;
        lastMintAt = uint64(block.timestamp);
        Tier tier = tokenId == 1 ? Tier.LegendaryGenesis : Tier.Genesis;
        _tier[tokenId] = tier;
        _artworkId[tokenId] = uint16(tokenId);
        emit GenesisMinted(msg.sender, tokenId, uint16(tokenId), GENESIS_PRICE);
        emit Revealed(tokenId, tier, uint16(tokenId));

        _safeMint(msg.sender, tokenId);
    }

    /// @notice Phase 2: burn 350,000 BMC and receive a pending-reveal NFT. No VRF request is made.
    function mintMystery() external nonReentrant returns (uint256 tokenId) {
        if (totalMinted < GENESIS_PHASE_SUPPLY) revert GenesisPhaseNotOver();
        if (totalMinted >= MAX_SUPPLY) revert SoldOut();
        if (saleClosed()) revert SaleIsClosed();

        _burnExact(msg.sender, MYSTERY_PRICE);

        tokenId = ++totalMinted;
        lastMintAt = uint64(block.timestamp);
        emit MysteryMinted(msg.sender, tokenId, MYSTERY_PRICE);

        _safeMint(msg.sender, tokenId);
    }

    /// @dev Burns exactly `amount` BMC from `payer` via burnFrom and verifies the burn happened.
    function _burnExact(address payer, uint256 amount) private {
        uint8 dec = BMC.decimals();
        if (dec != BMC_DECIMALS) revert UnexpectedTokenDecimals(dec);
        uint256 supplyBefore = BMC.totalSupply();
        uint256 balanceBefore = BMC.balanceOf(payer);
        BMC.burnFrom(payer, amount);
        uint256 supplyDelta = supplyBefore - BMC.totalSupply();
        uint256 balanceDelta = balanceBefore - BMC.balanceOf(payer);
        if (supplyDelta != amount || balanceDelta != amount) revert BurnMismatch(amount, supplyDelta);
        totalBurned += amount;
        assert(totalBurned <= MAX_TOTAL_BURN);
    }

    // ------------------------------------------------------------------------------------------
    // Sale close and seed request (permissionless)
    // ------------------------------------------------------------------------------------------

    /// @notice The sale is closed when sold out, or when `SALE_IDLE_TIMEOUT` has passed without a mint
    ///         once at least one mystery token exists. Closing is a pure function of state; no call is
    ///         needed. With exactly 40 Genesis minted the sale stays open however long it is idle, so a
    ///         closed sale always has something to reveal.
    function saleClosed() public view returns (bool) {
        if (totalMinted >= MAX_SUPPLY) return true;
        return totalMinted > GENESIS_PHASE_SUPPLY && block.timestamp >= uint256(lastMintAt) + SALE_IDLE_TIMEOUT;
    }

    /// @notice Timestamp of the latest seed request charged to the configured subscription (0 if none).
    function lastSeedRequestAt() external view returns (uint64) {
        return lastSeedRequestAtOf[SUBSCRIPTION_ID];
    }

    /// @notice Request the single VRF seed from the configured subscription and gas lane. Anyone may
    ///         call once the sale is closed; again after `SEED_REQUEST_TIMEOUT` if nothing arrived.
    function requestSeed() external returns (uint256 requestId) {
        return _requestSeed(SUBSCRIPTION_ID, KEY_HASH, false);
    }

    /// @notice Recovery: same as `requestSeed`, but from any subscription that lists this contract as a
    ///         consumer and on any gas lane the coordinator has a proving key for. Lets anyone pay for
    ///         the seed if the configured subscription or lane is unusable. The timeout applies per
    ///         subscription: a request here never delays `requestSeed`. The configured subscription may
    ///         only leave its lane once the coordinator no longer registers `KEY_HASH`, so a stranger
    ///         cannot pick a more expensive lane at the configured subscription's cost.
    function requestSeedWith(uint256 subscriptionId, bytes32 keyHash) external returns (uint256 requestId) {
        return _requestSeed(subscriptionId, keyHash, true);
    }

    function _requestSeed(uint256 subscriptionId, bytes32 keyHash, bool strictRegistry)
        private
        nonReentrant
        returns (uint256 requestId)
    {
        if (!saleClosed()) revert SaleNotClosed();
        if (seedSet) revert SeedAlreadyDelivered();
        uint64 lastAt = lastSeedRequestAtOf[subscriptionId];
        uint256 retryAt = uint256(lastAt) + SEED_REQUEST_TIMEOUT;
        if (lastAt != 0 && block.timestamp < retryAt) revert SeedRequestPending(retryAt);
        _checkKeyHash(keyHash, strictRegistry);
        if (subscriptionId == SUBSCRIPTION_ID && keyHash != KEY_HASH) {
            (, bool defaultExists) = _laneStatus(KEY_HASH);
            if (defaultExists) revert DefaultLaneStillRegistered(KEY_HASH);
        }

        requestId = VRF_COORDINATOR.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: NATIVE_PAYMENT}))
            })
        );
        require(requestId != 0 && !isSeedRequest[requestId], "duplicate request id");
        isSeedRequest[requestId] = true;
        lastSeedRequestAtOf[subscriptionId] = uint64(block.timestamp);
        uint32 attempt = ++seedRequestCount;
        emit SeedRequested(requestId, attempt, subscriptionId, keyHash);
    }

    /// @dev The mainnet coordinator does not validate key hashes in `requestRandomWords`; a request on
    ///      an unregistered lane is accepted and never fulfilled. Read its proving-key registry
    ///      (`s_provingKeys(bytes32) -> (bool exists, uint64 maxGas)`) before requesting. If the
    ///      coordinator does not expose the registry (test mocks), the default lane is accepted and the
    ///      recovery path is refused.
    function _checkKeyHash(bytes32 keyHash, bool strict) private view {
        (bool known, bool exists) = _laneStatus(keyHash);
        if (known) {
            if (!exists) revert KeyHashNotRegistered(keyHash);
        } else if (strict || keyHash != KEY_HASH) {
            revert KeyHashNotRegistered(keyHash);
        }
    }

    /// @dev `known` is false when the coordinator does not expose the registry.
    function _laneStatus(bytes32 keyHash) private view returns (bool known, bool exists) {
        (bool ok, bytes memory data) =
            address(VRF_COORDINATOR).staticcall(abi.encodeWithSignature("s_provingKeys(bytes32)", keyHash));
        known = ok && data.length >= 64;
        if (known) (exists,) = abi.decode(data, (bool, uint64));
    }

    // ------------------------------------------------------------------------------------------
    // Chainlink VRF v2.5 fulfillment
    // ------------------------------------------------------------------------------------------

    /// @notice Called by the VRF coordinator. The first word delivered for any request this contract
    ///         made becomes the seed; later deliveries are ignored. Nothing else happens here, so the
    ///         callback cannot run out of gas or fail for a reason outside this function.
    /// @dev Same signature as Chainlink's VRFConsumerBaseV2Plus so the coordinator can call it. Not
    ///      inherited: that base would give the owner `setCoordinator`.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(VRF_COORDINATOR)) revert OnlyCoordinator();
        if (!isSeedRequest[requestId]) revert UnknownRequest(requestId);
        if (randomWords.length == 0) revert NoRandomWords();
        if (seedSet) {
            emit SeedDeliveryIgnored(requestId, randomWords[0]);
            return;
        }
        seedSet = true;
        seed = randomWords[0];
        seedRequestId = requestId;
        emit SeedDelivered(requestId, randomWords[0]);
    }

    /// @notice Permissionless: materialize up to `maxCount` outcomes into storage, in mint order,
    ///         emitting `Revealed`. Outcomes and metadata are already final once the seed is set; this
    ///         only makes views O(1) and feeds indexers. Returns how many were materialized.
    function finalizeReveals(uint256 maxCount) external returns (uint256 done) {
        if (!seedSet) return 0;
        uint256 tokenId = GENESIS_PHASE_SUPPLY + revealedCount + 1;
        while (done < maxCount && tokenId <= totalMinted) {
            _finalize(tokenId);
            unchecked {
                ++tokenId;
                ++done;
            }
        }
    }

    /// @dev One step of the virtual Fisher-Yates shuffle in storage (O(1) gas), identical to
    ///      `MysteryDraw.slotAt(seed, revealedCount)`.
    function _finalize(uint256 tokenId) private {
        uint256 step = revealedCount;
        uint256 r = MysteryDraw.pick(seed, step);
        uint256 lastIndex = MYSTERY_SUPPLY - 1 - step;
        uint256 picked = _slotValue(r);
        _slotSwap[r] = _slotValue(lastIndex) + 1;
        delete _slotSwap[lastIndex];
        revealedCount = step + 1;

        (bool genesis, uint16 artwork) = MysteryDraw.decode(picked);
        Tier tier = genesis ? Tier.Genesis : Tier.Standard;
        if (genesis) mysteryGenesisRevealed += 1;
        _tier[tokenId] = tier;
        _artworkId[tokenId] = artwork;
        emit Revealed(tokenId, tier, artwork);
    }

    function _slotValue(uint256 i) private view returns (uint256) {
        uint256 s = _slotSwap[i];
        return s == 0 ? i : s - 1;
    }

    // ------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------

    /// @dev Tier and artwork of any minted token: stored for Genesis-phase and materialized tokens,
    ///      derived from the seed for the rest, Pending before the seed.
    function _outcome(uint256 tokenId) private view returns (Tier tier, uint16 artwork) {
        tier = _tier[tokenId];
        if (tier != Tier.Pending) return (tier, _artworkId[tokenId]);
        if (!seedSet) return (Tier.Pending, 0);
        (bool genesis, uint16 art) = MysteryDraw.decode(MysteryDraw.slotAt(seed, tokenId - GENESIS_PHASE_SUPPLY - 1));
        return (genesis ? Tier.Genesis : Tier.Standard, art);
    }

    function tierOf(uint256 tokenId) external view returns (Tier tier) {
        _requireMinted(tokenId);
        (tier,) = _outcome(tokenId);
    }

    /// @notice Artwork identifier: for Genesis tiers the genesis-NN number (1..77); for Standard the
    ///         on-chain artwork index (1..423); 0 while pending.
    function artworkIdOf(uint256 tokenId) external view returns (uint16 artwork) {
        _requireMinted(tokenId);
        (, artwork) = _outcome(tokenId);
    }

    function revealStatusOf(uint256 tokenId) external view returns (RevealStatus) {
        _requireMinted(tokenId);
        if (tokenId <= GENESIS_PHASE_SUPPLY || _tier[tokenId] != Tier.Pending) return RevealStatus.Revealed;
        return seedSet ? RevealStatus.RandomnessStored : RevealStatus.AwaitingRandomness;
    }

    /// @notice Kept for the mint site: the images directory is a constant now.
    function genesisImagesCID() external pure returns (string memory) {
        return GENESIS_IMAGES_CID;
    }

    /// @notice Earliest time at which `requestSeed` (configured subscription) can be called; 0 when it
    ///         cannot be predicted yet (no mystery token minted, so the sale cannot close by idle time)
    ///         or when the seed is already set. Shares its conditions with `saleClosed`.
    function seedRequestAvailableAt() external view returns (uint256) {
        if (seedSet) return 0;
        uint64 lastAt = lastSeedRequestAtOf[SUBSCRIPTION_ID];
        if (lastAt != 0) return uint256(lastAt) + SEED_REQUEST_TIMEOUT;
        if (totalMinted >= MAX_SUPPLY) return block.timestamp;
        if (totalMinted > GENESIS_PHASE_SUPPLY) return uint256(lastMintAt) + SALE_IDLE_TIMEOUT;
        return 0;
    }

    function totalSupply() external view returns (uint256) {
        return totalMinted;
    }

    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }

    function genesisPhaseActive() external view returns (bool) {
        return totalMinted < GENESIS_PHASE_SUPPLY;
    }

    /// @notice Mystery mint positions not yet sold (0 once the sale is closed).
    function remainingMysteryMints() external view returns (uint256) {
        if (totalMinted < GENESIS_PHASE_SUPPLY) return MYSTERY_SUPPLY;
        return saleClosed() ? 0 : MAX_SUPPLY - totalMinted;
    }

    /// @notice Mystery mints sold whose outcome is not yet materialized.
    function pendingReveals() external view returns (uint256) {
        return totalMinted < GENESIS_PHASE_SUPPLY ? 0 : (totalMinted - GENESIS_PHASE_SUPPLY) - revealedCount;
    }

    /// @notice Outcomes still inside the random pool (includes outcomes owed to pending tokens).
    function remainingMysteryGenesis() external view returns (uint256) {
        return MYSTERY_GENESIS - mysteryGenesisRevealed;
    }

    function remainingMysteryStandard() external view returns (uint256) {
        return TOTAL_STANDARD - (revealedCount - mysteryGenesisRevealed);
    }

    /// @notice Current price of the next mint in BMC units, 0 when sold out or closed.
    function currentPrice() external view returns (uint256) {
        if (totalMinted < GENESIS_PHASE_SUPPLY) return GENESIS_PRICE;
        return saleClosed() ? 0 : MYSTERY_PRICE;
    }

    function _requireMinted(uint256 tokenId) private view {
        if (tokenId == 0 || tokenId > totalMinted) revert NonexistentToken(tokenId);
    }

    // ------------------------------------------------------------------------------------------
    // Metadata (fully on-chain JSON)
    // ------------------------------------------------------------------------------------------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        (Tier tier, uint16 artwork) = _outcome(tokenId);
        string memory json;
        if (tier == Tier.Pending) {
            json = _pendingJson(tokenId);
        } else if (tier == Tier.Standard) {
            json = _standardJson(tokenId, artwork);
        } else {
            json = _genesisJson(tokenId, tier, artwork);
        }
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @notice Raw SVG of a Standard token (reverts for other tiers).
    function standardSVG(uint256 tokenId) external view returns (string memory) {
        _requireMinted(tokenId);
        (Tier tier, uint16 artwork) = _outcome(tokenId);
        require(tier == Tier.Standard, "not standard");
        return StandardArt.render(artwork);
    }

    function _genesisFile(uint16 artwork) private pure returns (string memory) {
        return string.concat("genesis-", artwork < 10 ? "0" : "", uint256(artwork).toString(), ".png");
    }

    function _genesisJson(uint256 tokenId, Tier tier, uint16 artwork) private pure returns (string memory) {
        bool legendary = tier == Tier.LegendaryGenesis;
        string memory file = _genesisFile(artwork);
        string memory head = string.concat(
            '{"name":"BMC Illuminati Pass #',
            tokenId.toString(),
            legendary ? " - Legendary Genesis" : " - Genesis",
            '","description":"',
            legendary
                ? "The one. The first BMC Illuminati Pass ever minted: the Legendary Genesis, the rarest piece of the 500-piece collection. A mysterious hooded frog with a glowing golden third eye, crowned and veiled, beneath the floating golden eye-in-triangle. Minted by permanently burning 1,000,000 BMC."
                : "A Genesis BMC Illuminati Pass. A mysterious cartoon frog in a black hooded cloak with premium gold-and-black styling, a glowing golden third eye and a floating golden eye-in-triangle. One of 77 Genesis pieces in a 500-piece collection minted by permanently burning BMC.",
            '","image":"ipfs://',
            GENESIS_IMAGES_CID,
            "/",
            file
        );
        string memory attrs = string.concat(
            '","attributes":[{"trait_type":"Tier","value":"',
            legendary ? "Legendary Genesis" : "Genesis",
            '"},{"trait_type":"Artwork","value":"',
            file,
            '"},{"trait_type":"Cloak","value":"Black Hooded, Gold Trim"},{"trait_type":"Third Eye","value":"Glowing Gold"},{"trait_type":"Sigil","value":"Floating Golden Eye-in-Triangle"}',
            legendary
                ? ',{"trait_type":"Crown","value":"Legendary Golden Crown"},{"trait_type":"Aura","value":"Radiant Gold Halo"},{"trait_type":"Rank","value":"First Minter"}'
                : "",
            ',{"trait_type":"Genesis Number","display_type":"number","value":',
            uint256(artwork).toString(),
            "}]}"
        );
        return string.concat(head, attrs);
    }

    function _standardJson(uint256 tokenId, uint16 artwork) private pure returns (string memory) {
        return string.concat(
            '{"name":"BMC Illuminati Pass #',
            tokenId.toString(),
            ' - Standard","description":"A Standard BMC Illuminati Pass. An original cartoon frog in a dark hooded cloak, rendered fully on-chain as SVG. One of 423 Standard pieces in a 500-piece collection minted by permanently burning BMC.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(StandardArt.render(artwork))),
            '","attributes":[{"trait_type":"Tier","value":"Standard"},{"trait_type":"Artwork","value":"standard-',
            uint256(artwork).toString(),
            '"},',
            StandardArt.attributesJson(artwork),
            "]}"
        );
    }

    function _pendingJson(uint256 tokenId) private pure returns (string memory) {
        string memory svg =
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400' width='400' height='400'><rect width='400' height='400' fill='#0b0b14'/><circle cx='200' cy='190' r='90' fill='none' stroke='#555' stroke-width='6' stroke-dasharray='12 10'/><text x='200' y='200' font-family='monospace' font-size='48' fill='#888' text-anchor='middle'>?</text><text x='200' y='330' font-family='monospace' font-size='16' fill='#888' text-anchor='middle'>BMC ILLUMINATI PASS</text><text x='200' y='355' font-family='monospace' font-size='14' fill='#666' text-anchor='middle'>REVEAL PENDING (Chainlink VRF)</text></svg>";
        return string.concat(
            '{"name":"BMC Illuminati Pass #',
            tokenId.toString(),
            ' - Pending Reveal","description":"A BMC Illuminati Pass mystery mint awaiting the Chainlink VRF seed requested once the sale closes. The outcome (Genesis or Standard) is not yet determined on-chain. Metadata becomes permanent once the seed is delivered.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[{"trait_type":"Tier","value":"Pending Reveal"}]}'
        );
    }
}
