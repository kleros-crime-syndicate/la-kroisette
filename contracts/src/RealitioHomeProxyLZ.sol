// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OApp, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IForeignArbitrationProxy, IHomeArbitrationProxy} from "./interfaces/IArbitrationProxies.sol";
import {IRealitio} from "./interfaces/IRealitio.sol";

/**
 * @dev Minimal LayerZero-v2 rewrite of RealitioHomeProxy
 */
abstract contract RealitioHomeProxyLZ is OApp, IHomeArbitrationProxy {

    IRealitio public immutable realitio; // trusted
    uint32 public immutable foreignEid; // LayerZero endpointId of the foreign chain
    address public immutable foreignProxy; // trusted

    string public override metadata;

    enum Status {
        None,
        Rejected,
        Notified,
        AwaitingRuling,
        Ruled,
        Finished
    }
    struct Request {
        Status status;
        bytes32 arbitratorAnswer;
    }
    mapping(bytes32 => mapping(address => Request)) public requests;
    mapping(bytes32 => address) public questionIDToRequester;

    constructor(
        address _endpoint, // LayerZero endpoint for *this* chain
        IRealitio _realitio,
        string memory _metadata,
        uint32 _foreignEid,
        address _foreignProxy
    ) OApp(_endpoint, msg.sender) {
        realitio = _realitio;
        metadata = _metadata;
        foreignEid = _foreignEid;
        foreignProxy = _foreignProxy;
    }

    function _lzReceive(
        uint32 _srcEid,
        bytes32 _sender,
        bytes calldata _payload,
        address /* executor */,
        bytes calldata /* extraData */
    ) internal {
        require(_srcEid == foreignEid, "wrong src");
        require(
            address(uint160(uint256(_sender))) == foreignProxy,
            "wrong proxy"
        );

        (uint8 tag, bytes memory data) = abi.decode(_payload, (uint8, bytes));
        if (tag == 0x01) {
            (bytes32 q, address r, uint256 maxPrev) = abi.decode(
                data,
                (bytes32, address, uint256)
            );
            _receiveArbitrationRequest(q, r, maxPrev);
        } else if (tag == 0x02) {
            (bytes32 q, address r) = abi.decode(data, (bytes32, address));
            _receiveArbitrationFailure(q, r);
        } else if (tag == 0x03) {
            (bytes32 q, bytes32 ans) = abi.decode(data, (bytes32, bytes32));
            receiveArbitrationAnswer(q, ans);
        } else {
            revert("unknown tag");
        }
    }

    function _receiveArbitrationRequest(
        bytes32 q,
        address requester,
        uint256 maxPrev
    ) private {
        Request storage req = requests[q][requester];
        require(req.status == Status.None, "exists");
        try realitio.notifyOfArbitrationRequest(q, requester, maxPrev) {
            req.status = Status.Notified;
            questionIDToRequester[q] = requester;
            emit RequestNotified(q, requester, maxPrev);
        } catch {
            req.status = Status.Rejected;
            emit RequestRejected(q, requester, maxPrev, "");
        }
    }

    function _receiveArbitrationFailure(bytes32 q, address requester) private {
        Request storage req = requests[q][requester];
        require(req.status == Status.AwaitingRuling, "bad status");
        req.status = Status.None;
        // Note: cancelArbitration is not available in the IRealitio interface
        // The arbitration failure is handled by status change
        emit ArbitrationFailed(q, requester);
    }

    function _send(uint8 tag, bytes memory data) internal {
        bytes memory payload = abi.encode(tag, data);
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), 200000, 0);
        // Get the fee first
        MessagingFee memory fee = _quote(foreignEid, payload, options, false);
        _lzSend(
            foreignEid,
            payload,
            options,
            fee,
            payable(msg.sender) // refunds go to caller
        );
    }

    function handleNotifiedRequest(
        bytes32 q,
        address requester
    ) external override {
        Request storage req = requests[q][requester];
        require(req.status == Status.Notified, "bad status");
        req.status = Status.AwaitingRuling;
        _send(0x10, abi.encode(q, requester)); // tag 0x10 = acknowledgement
        emit RequestAcknowledged(q, requester);
    }

    function handleRejectedRequest(
        bytes32 q,
        address requester
    ) external override {
        Request storage req = requests[q][requester];
        require(req.status == Status.Rejected, "bad status");
        req.status = Status.None;
        _send(0x11, abi.encode(q, requester)); // tag 0x11 = cancel
        emit RequestCanceled(q, requester);
    }

    function receiveArbitrationAnswer(
        bytes32 q,
        bytes32 answer
    ) public override {
        address requester = questionIDToRequester[q];
        Request storage req = requests[q][requester];
        require(req.status == Status.AwaitingRuling, "bad status");
        req.status = Status.Ruled;
        req.arbitratorAnswer = answer;
        emit ArbitratorAnswered(q, answer);
    }

    function reportArbitrationAnswer(
        bytes32 q,
        bytes32 lastHist,
        bytes32 lastAnsID,
        address lastAns
    ) external {
        address requester = questionIDToRequester[q];
        Request storage req = requests[q][requester];
        require(req.status == Status.Ruled, "not ruled");
        req.status = Status.Finished;
        realitio.assignWinnerAndSubmitAnswerByArbitrator(
            q,
            req.arbitratorAnswer,
            requester,
            lastHist,
            lastAnsID,
            lastAns
        );
        emit ArbitrationFinished(q);
    }
}
