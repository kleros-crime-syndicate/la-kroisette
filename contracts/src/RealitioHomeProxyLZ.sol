// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRealitio} from "./interfaces/IRealitio.sol";
import {IHomeArbitrationProxy} from "./interfaces/IArbitrationProxies.sol";
import "./Constants.sol";

/**
 * @title Arbitration proxy for Realitio on the side-chain side (A.K.A. the Home Chain).
 * @dev This contract is meant to be deployed to side-chains in which Reality.eth is deployed.
 */
contract RealitioHomeProxyLZ is OApp, OAppOptionsType3, IHomeArbitrationProxy {
    /// @dev The address of the Realitio contract (v2.1+ required). TRUSTED.
    IRealitio public immutable realitio;

    /// @dev The endpoint ID where the foreign proxy is deployed.
    uint32 public immutable foreignEid;

    /// @dev Metadata for Realitio interface.
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

    /// @dev Associates an arbitration request with a question ID and a requester address. requests[questionID][requester]
    mapping(bytes32 => mapping(address => Request)) public requests;

    /// @dev Associates a question ID with the requester who succeeded in requesting arbitration. questionIDToRequester[questionID]
    mapping(bytes32 => address) public questionIDToRequester;

    /**
     * @notice Creates an arbitration proxy on the home chain.
     * @param _realitio Realitio contract address.
     * @param _metadata Metadata for Realitio.
     * @param _foreignEid The endpoint ID where the foreign proxy is deployed.
     * @param _endpoint The LayerZero endpoint address.
     */
    constructor(
        IRealitio _realitio,
        string memory _metadata,
        uint32 _foreignEid,
        address _endpoint
    ) OApp(_endpoint, msg.sender) Ownable(msg.sender) {
        realitio = _realitio;
        metadata = _metadata;
        foreignEid = _foreignEid;
    }

    /**
     * @notice Allows the contract to receive ETH deposits for LayerZero fees.
     */
    receive() external payable {}

    /**
     * @notice Allows the owner to withdraw ETH from the contract.
     * @param _amount The amount of ETH to withdraw.
     */
    function withdrawETH(uint256 _amount) external onlyOwner {
        require(_amount <= address(this).balance, "Insufficient balance");
        payable(owner()).transfer(_amount);
    }

    /**
     * @notice LayerZero message receive function.
     * @dev Routes incoming messages to appropriate handler functions.
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        // Decode message type first
        uint16 msgType;
        bytes memory payload;
        
        try this._decodeMessage(_message) returns (uint16 _msgType, bytes memory _payload) {
            msgType = _msgType;
            payload = _payload;
        } catch {
            revert("Invalid message format");
        }
        
        // Route message based on type
        if (msgType == MSG_TYPE_ARBITRATION_REQUEST) {
            try this._decodeArbitrationRequest(payload) returns (bytes32 questionID, address requester, uint256 maxPrevious) {
                _handleArbitrationRequest(questionID, requester, maxPrevious);
            } catch {
                revert("Invalid arbitration request payload");
            }
        } else if (msgType == MSG_TYPE_ARBITRATION_FAILURE) {
            try this._decodeArbitrationFailure(payload) returns (bytes32 questionID, address requester) {
                _handleArbitrationFailure(questionID, requester);
            } catch {
                revert("Invalid arbitration failure payload");
            }
        } else if (msgType == MSG_TYPE_ARBITRATION_ANSWER) {
            try this._decodeArbitrationAnswer(payload) returns (bytes32 questionID, bytes32 answer) {
                _handleArbitrationAnswer(questionID, answer);
            } catch {
                revert("Invalid arbitration answer payload");
            }
        } else {
            revert("Unknown message type");
        }
    }

    /**
     * @notice External decoder functions for safe message parsing.
     * @dev These are marked external to be called via try/catch for error handling.
     */
    function _decodeMessage(bytes calldata _message) external pure returns (uint16 msgType, bytes memory payload) {
        return abi.decode(_message, (uint16, bytes));
    }

    function _decodeArbitrationRequest(bytes memory _payload) external pure returns (bytes32 questionID, address requester, uint256 maxPrevious) {
        return abi.decode(_payload, (bytes32, address, uint256));
    }

    function _decodeArbitrationFailure(bytes memory _payload) external pure returns (bytes32 questionID, address requester) {
        return abi.decode(_payload, (bytes32, address));
    }

    function _decodeArbitrationAnswer(bytes memory _payload) external pure returns (bytes32 questionID, bytes32 answer) {
        return abi.decode(_payload, (bytes32, bytes32));
    }

    /**
     * @dev Receives the requested arbitration for a question. TRUSTED.
     * @param _questionID The ID of the question.
     * @param _requester The address of the user that requested arbitration.
     * @param _maxPrevious The maximum value of the previous bond for the question.
     */
    function receiveArbitrationRequest(
        bytes32 _questionID,
        address _requester,
        uint256 _maxPrevious
    ) external override {
        _handleArbitrationRequest(_questionID, _requester, _maxPrevious);
    }

    /**
     * @dev Internal handler for arbitration requests.
     */
    function _handleArbitrationRequest(
        bytes32 _questionID,
        address _requester,
        uint256 _maxPrevious
    ) internal {
        require(_questionID != bytes32(0), "Question ID cannot be empty");
        require(_requester != address(0), "Requester cannot be zero address");
        
        Request storage request = requests[_questionID][_requester];
        require(request.status == Status.None, "Request already exists");

        try
            realitio.notifyOfArbitrationRequest(
                _questionID,
                _requester,
                _maxPrevious
            )
        {
            request.status = Status.Notified;
            questionIDToRequester[_questionID] = _requester;

            emit RequestNotified(_questionID, _requester, _maxPrevious);
        } catch Error(string memory reason) {
            /*
             * Will fail if:
             *  - The question does not exist.
             *  - The question was not answered yet.
             *  - Another request was already accepted.
             *  - Someone increased the bond on the question to a value > _maxPrevious
             */
            request.status = Status.Rejected;

            emit RequestRejected(_questionID, _requester, _maxPrevious, reason);
        } catch {
            // In case `reject` did not have a reason string or some other error happened
            request.status = Status.Rejected;

            emit RequestRejected(_questionID, _requester, _maxPrevious, "");
        }
    }

    /**
     * @notice Handles arbitration request after it has been notified to Realitio for a given question.
     * @dev This method exists because `receiveArbitrationRequest` is called by the AMB and cannot send messages back to it.
     * @param _questionID The ID of the question.
     * @param _requester The address of the user that requested arbitration.
     */
    function handleNotifiedRequest(
        bytes32 _questionID,
        address _requester
    ) external override {
        Request storage request = requests[_questionID][_requester];
        require(request.status == Status.Notified, "Invalid request status");

        request.status = Status.AwaitingRuling;

        bytes memory message = abi.encode(
            MSG_TYPE_ARBITRATION_ACKNOWLEDGEMENT,
            _questionID,
            _requester
        );
        
        // LayerZero fee calculation
        bytes memory gasOptions = abi.encodePacked(uint16(1), uint128(200000)); // Set gas limit to 200,000 for acknowledgement processing
        bytes memory options = this.combineOptions(foreignEid, MSG_TYPE_ARBITRATION_ACKNOWLEDGEMENT, gasOptions);
        MessagingFee memory fee = _quote(foreignEid, message, options, false);
        
        // Check contract balance for LayerZero fee
        if (address(this).balance < fee.nativeFee) {
            revert InsufficientFundsForLayerZero(fee.nativeFee, address(this).balance);
        }
        
        _lzSend(
            foreignEid,
            message,
            options,
            MessagingFee(fee.nativeFee, 0),
            payable(address(this))
        );

        emit RequestAcknowledged(_questionID, _requester);
    }

    /**
     * @notice Handles arbitration request after it has been rejected.
     * @dev This method exists because `receiveArbitrationRequest` is called by the AMB and cannot send messages back to it.
     * Reasons why the request might be rejected:
     *  - The question does not exist
     *  - The question was not answered yet
     *  - The question bond value changed while the arbitration was being requested
     *  - Another request was already accepted
     * @param _questionID The ID of the question.
     * @param _requester The address of the user that requested arbitration.
     */
    function handleRejectedRequest(
        bytes32 _questionID,
        address _requester
    ) external override {
        Request storage request = requests[_questionID][_requester];
        require(request.status == Status.Rejected, "Invalid request status");

        // At this point, only the request.status is set, simply resetting the status to Status.None is enough.
        request.status = Status.None;

        bytes memory message = abi.encode(
            MSG_TYPE_ARBITRATION_CANCELATION,
            _questionID,
            _requester
        );
        
        // LayerZero fee calculation
        bytes memory gasOptions = abi.encodePacked(uint16(1), uint128(150000)); // Set gas limit to 150,000 for cancelation processing
        bytes memory options = this.combineOptions(foreignEid, MSG_TYPE_ARBITRATION_CANCELATION, gasOptions);
        MessagingFee memory fee = _quote(foreignEid, message, options, false);
        
        // Check contract balance for LayerZero fee
        if (address(this).balance < fee.nativeFee) {
            revert InsufficientFundsForLayerZero(fee.nativeFee, address(this).balance);
        }
        
        _lzSend(
            foreignEid,
            message,
            options,
            MessagingFee(fee.nativeFee, 0),
            payable(address(this))
        );

        emit RequestCanceled(_questionID, _requester);
    }

    /**
     * @notice Receives a failed attempt to request arbitration. TRUSTED.
     * @dev Currently this can happen only if the arbitration cost increased.
     * @param _questionID The ID of the question.
     * @param _requester The address of the user that requested arbitration.
     */
    function receiveArbitrationFailure(
        bytes32 _questionID,
        address _requester
    ) external override {
        _handleArbitrationFailure(_questionID, _requester);
    }

    /**
     * @dev Internal handler for arbitration failures.
     */
    function _handleArbitrationFailure(
        bytes32 _questionID,
        address _requester
    ) internal {
        require(_questionID != bytes32(0), "Question ID cannot be empty");
        require(_requester != address(0), "Requester cannot be zero address");
        
        Request storage request = requests[_questionID][_requester];
        require(
            request.status == Status.AwaitingRuling,
            "Invalid request status"
        );

        // At this point, only the request.status is set, simply resetting the status to Status.None is enough.
        request.status = Status.None;

        realitio.cancelArbitration(_questionID);

        emit ArbitrationFailed(_questionID, _requester);
    }

    /**
     * @notice Receives an answer to a specified question. TRUSTED.
     * @param _questionID The ID of the question.
     * @param _answer The answer from the arbitrator.
     */
    function receiveArbitrationAnswer(
        bytes32 _questionID,
        bytes32 _answer
    ) external override {
        _handleArbitrationAnswer(_questionID, _answer);
    }

    /**
     * @dev Internal handler for arbitration answers.
     */
    function _handleArbitrationAnswer(
        bytes32 _questionID,
        bytes32 _answer
    ) internal {
        require(_questionID != bytes32(0), "Question ID cannot be empty");
        
        address requester = questionIDToRequester[_questionID];
        require(requester != address(0), "No requester found for question");
        
        Request storage request = requests[_questionID][requester];
        require(
            request.status == Status.AwaitingRuling,
            "Invalid request status"
        );

        request.status = Status.Ruled;
        request.arbitratorAnswer = _answer;

        emit ArbitratorAnswered(_questionID, _answer);
    }

    /**
     * @notice Reports the answer provided by the arbitrator to a specified question.
     * @dev The Realitio contract validates the input parameters passed to this method,
     * so making this publicly accessible is safe.
     * @param _questionID The ID of the question.
     * @param _lastHistoryHash The history hash given with the last answer to the question in the Realitio contract.
     * @param _lastAnswerOrCommitmentID The last answer given, or its commitment ID if it was a commitment,
     * to the question in the Realitio contract.
     * @param _lastAnswerer The last answerer to the question in the Realitio contract.
     */
    function reportArbitrationAnswer(
        bytes32 _questionID,
        bytes32 _lastHistoryHash,
        bytes32 _lastAnswerOrCommitmentID,
        address _lastAnswerer
    ) external {
        address requester = questionIDToRequester[_questionID];
        Request storage request = requests[_questionID][requester];
        require(request.status == Status.Ruled, "Arbitrator has not ruled yet");

        request.status = Status.Finished;

        realitio.assignWinnerAndSubmitAnswerByArbitrator(
            _questionID,
            request.arbitratorAnswer,
            requester,
            _lastHistoryHash,
            _lastAnswerOrCommitmentID,
            _lastAnswerer
        );

        emit ArbitrationFinished(_questionID);
    }
}
