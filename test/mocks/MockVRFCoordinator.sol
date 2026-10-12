// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

interface IRawFulfill {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

/// @dev Minimal VRF v2.5 coordinator stand-in modelled on the mainnet VRFCoordinatorV2_5 behaviour
///      that matters here: it exposes the proving-key registry `s_provingKeys(bytes32)` but, like the
///      real coordinator, accepts requests for any key hash and any subscription balance. Tests decide
///      which requests are ever fulfilled, in which order, and with how much callback gas.
contract MockVRFCoordinator {
    struct Req {
        address consumer;
        uint32 callbackGasLimit;
        bool fulfilled;
        bytes32 keyHash;
        uint256 subId;
        uint16 confirmations;
        bool nativePayment;
    }

    struct ProvingKey {
        bool exists;
        uint64 maxGas;
    }

    /// @dev Mainnet 500 gwei lane, registered by default.
    bytes32 public constant REGISTERED_KEY_HASH = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b;

    uint256 public nextRequestId = 1000;
    mapping(uint256 => Req) public requests;
    mapping(bytes32 => ProvingKey) private _provingKeys;
    bool public rejectRequests;
    bool public hideRegistry;
    uint256 public requestCount;

    constructor() {
        _provingKeys[REGISTERED_KEY_HASH] = ProvingKey({exists: true, maxGas: 500 gwei});
    }

    /// @dev Same ABI as the mainnet coordinator's public `s_provingKeys` mapping.
    function s_provingKeys(bytes32 keyHash) external view returns (bool exists, uint64 maxGas) {
        require(!hideRegistry, "mock: no registry");
        ProvingKey memory k = _provingKeys[keyHash];
        return (k.exists, k.maxGas);
    }

    function setRejectRequests(bool v) external {
        rejectRequests = v;
    }

    function setProvingKey(bytes32 keyHash, bool exists) external {
        _provingKeys[keyHash] = ProvingKey({exists: exists, maxGas: exists ? 500 gwei : 0});
    }

    /// @dev When set, the registry view reverts (simulates a coordinator without `s_provingKeys`).
    function setHideRegistry(bool v) external {
        hideRegistry = v;
    }

    fallback() external {
        revert("mock: unknown function");
    }

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256 id) {
        require(!rejectRequests, "mock: request rejected");
        id = nextRequestId++;
        requestCount++;
        VRFV2PlusClient.ExtraArgsV1 memory ea = abi.decode(_stripSelector(req.extraArgs), (VRFV2PlusClient.ExtraArgsV1));
        requests[id] = Req({
            consumer: msg.sender,
            callbackGasLimit: req.callbackGasLimit,
            fulfilled: false,
            keyHash: req.keyHash,
            subId: req.subId,
            confirmations: req.requestConfirmations,
            nativePayment: ea.nativePayment
        });
    }

    /// @dev Fulfil using the request's own callback gas limit, like the real coordinator. Like the
    ///      real coordinator the request is consumed whether or not the callback succeeded.
    function fulfill(uint256 requestId, uint256 word) external returns (bool ok) {
        return fulfillWithGas(requestId, word, requests[requestId].callbackGasLimit);
    }

    function fulfillWithGas(uint256 requestId, uint256 word, uint256 gas) public returns (bool ok) {
        Req storage r = requests[requestId];
        require(r.consumer != address(0), "mock: unknown request");
        require(!r.fulfilled, "mock: already fulfilled");
        r.fulfilled = true;
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        (ok,) = r.consumer.call{gas: gas}(abi.encodeCall(IRawFulfill.rawFulfillRandomWords, (requestId, words)));
    }

    /// @dev Re-deliver an already fulfilled request (should be ignored by the consumer).
    function redeliver(uint256 requestId, uint256 word) external returns (bool ok) {
        Req storage r = requests[requestId];
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        (ok,) = r.consumer.call(abi.encodeCall(IRawFulfill.rawFulfillRandomWords, (requestId, words)));
    }

    function _stripSelector(bytes calldata data) private pure returns (bytes memory) {
        return data[4:];
    }
}
