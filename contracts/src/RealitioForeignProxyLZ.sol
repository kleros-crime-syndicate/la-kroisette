// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OApp, OAppOptions} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {IDisputeResolver, IArbitrator} from "@kleros/dispute-resolver-interface-contract-0.8/contracts/IDisputeResolver.sol";
import {IForeignArbitrationProxy, IHomeArbitrationProxy} from "./interfaces/IArbitrationProxies.sol";
import {SafeSend} from "./libraries/SafeSend.sol";

/**
 * @dev Minimal LayerZero-v2 rewrite of RealitioForeignProxy
 *      *Only the bridging parts were changed – all Kleros logic kept intact.*
 */
contract RealitioForeignProxyLZ is
    OApp,
    IForeignArbitrationProxy,
    IDisputeResolver
{
    using SafeSend for address payable;

    // ---- original immutable/constant fields unchanged ----
    uint256 public constant NUMBER_OF_CHOICES_FOR_ARBITRATOR =
        type(uint256).max;
    uint256 public constant REFUSE_TO_ARBITRATE_REALITIO = type(uint256).max;
    uint256 public constant MULTIPLIER_DIVISOR = 10000;
    uint256 public constant META_EVIDENCE_ID = 0;

    address public immutable wNative;
    IArbitrator public immutable arbitrator;
    bytes public arbitratorExtraData;

    uint32 public immutable homeEid;
    address public immutable homeProxy;

    // … (Status enum, structs, mappings – copy-pasted, unchanged)

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(
        address _endpoint, // LZ endpoint on *this* chain
        uint32 _homeEid,
        address _homeProxy,
        address _wNative,
        IArbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        string memory _metaEvidence,
        uint256 _winnerMult,
        uint256 _loserMult,
        uint256 _loserAppealMult
    ) OApp(_endpoint) {
        homeEid = _homeEid;
        homeProxy = _homeProxy;
        wNative = _wNative;
        arbitrator = _arbitrator;
        arbitratorExtraData = _arbitratorExtraData;
        winnerMultiplier = _winnerMult;
        loserMultiplier = _loserMult;
        loserAppealPeriodMultiplier = _loserAppealMult;
        emit MetaEvidence(META_EVIDENCE_ID, _metaEvidence);
    }

    // ---------------------------------------------------------------------
    //  LayerZero receive
    // ---------------------------------------------------------------------

    function _lzReceive(
        uint32 _srcEid,
        bytes32 _sender,
        bytes calldata _payload,
        address /* executor */,
        bytes calldata /* extraData */
    ) internal override {
        require(_srcEid == homeEid, "wrong src");
        require(address(uint160(uint256(_sender))) == homeProxy, "wrong proxy");

        (uint8 tag, bytes memory data) = abi.decode(_payload, (uint8, bytes));

        if (tag == 0x10) {
            // acknowledgement
            (bytes32 q, address requester) = abi.decode(
                data,
                (bytes32, address)
            );
            _receiveArbitrationAck(q, requester);
        } else if (tag == 0x11) {
            // cancel
            (bytes32 q, address requester) = abi.decode(
                data,
                (bytes32, address)
            );
            _receiveArbitrationCancel(q, requester);
        } else if (tag == 0x03) {
            // answer relay from home (unlikely but kept)
            (bytes32 q, bytes32 ans) = abi.decode(data, (bytes32, bytes32));
            // not used in this direction
        }
    }

    // ---------------------------------------------------------------------
    //  Outgoing send helper
    // ---------------------------------------------------------------------

    function _send(uint8 tag, bytes memory data) internal {
        _lzSend(
            homeEid,
            abi.encode(tag, data),
            OAppOptions.build(uint16(1), 0, new bytes(0)),
            payable(msg.sender)
        );
    }

    // ---------------------------------------------------------------------
    //  Bridging-aware rewrites of original AMB calls
    // ---------------------------------------------------------------------

    function _requestArbitration(
        bytes32 q,
        uint256 maxPrev,
        uint256 /* gas */ // gas param no longer needed with OMP
    ) internal override {
        // (all original bookkeeping kept exactly the same …)
        // …
        // instead of amb.requireToPassMessage:
        _send(0x01, abi.encode(q, msg.sender, maxPrev));
        emit ArbitrationRequested(q, msg.sender, maxPrev);
    }

    function _receiveArbitrationAck(bytes32 q, address requester) private {
        // original body of receiveArbitrationAcknowledgement
        _receiveArbitrationAcknowledgement(q, requester);
    }

    function _receiveArbitrationCancel(bytes32 q, address requester) private {
        // original body of receiveArbitrationCancelation
        _receiveArbitrationCancelation(q, requester);
    }

    function _relayRule(
        bytes32 q,
        address requester,
        uint256 /* gas */
    ) internal override {
        // original bookkeeping …
        // instead of amb.requireToPassMessage:
        _send(0x03, abi.encode(q, bytes32(realitioRuling)));
        emit RulingRelayed(q, bytes32(realitioRuling));
    }

    // ---- the rest of the original proxy (appeal funding, withdrawals, rule, etc.) is unchanged ----
}
