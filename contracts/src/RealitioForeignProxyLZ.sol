// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IArbitrableV2, IArbitratorV2} from "@kleros/kleros-v2-contracts/arbitration/interfaces/IArbitratorV2.sol";
import {IDisputeTemplateRegistry} from "@kleros/kleros-v2-contracts/arbitration/interfaces/IDisputeTemplateRegistry.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IForeignArbitrationProxy} from "./interfaces/IArbitrationProxies.sol";
import {SafeSend} from "./libraries/SafeSend.sol";
import "./Constants.sol";

/**
 * @title Arbitration proxy for Realitio on Ethereum side (A.K.A. the Foreign Chain).
 * @dev This contract is meant to be deployed to the Ethereum chains where Kleros is deployed.
 */
contract RealitioForeignProxyLZ is
    OApp,
    OAppOptionsType3,
    IForeignArbitrationProxy,
    IArbitrableV2
{
    using SafeSend for address payable;

    /* Constants */
    uint256 public constant NUMBER_OF_CHOICES_FOR_ARBITRATOR =
        type(uint256).max; // The number of choices for the arbitrator.
    uint256 public constant REFUSE_TO_ARBITRATE_REALITIO = type(uint256).max; // Constant that represents "Refuse to rule" in realitio format.

    /* Storage */

    enum Status {
        None,
        Requested,
        Created,
        Ruled,
        Relayed,
        Failed
    }

    struct ArbitrationRequest {
        Status status; // Status of the arbitration.
        uint248 deposit; // The deposit paid by the requester at the time of the arbitration.
        uint256 disputeID; // The ID of the dispute in arbitrator contract.
        uint256 answer; // The answer given by the arbitrator.
    }

    struct DisputeDetails {
        uint256 arbitrationID; // The ID of the arbitration.
        address requester; // The address of the requester who managed to go through with the arbitration request.
    }

    address public immutable wNative; // Address of wrapped version of the chain's native currency. WETH-like.

    IArbitratorV2 public immutable arbitrator; // The address of the arbitrator. TRUSTED.
    bytes public arbitratorExtraData; // The extra data used to raise a dispute in the arbitrator.
    IDisputeTemplateRegistry public immutable templateRegistry; // The dispute template registry. TRUSTED.

    uint32 public immutable homeEid; // The endpoint ID where the home proxy is deployed.

    mapping(uint256 => mapping(address => ArbitrationRequest))
        public arbitrationRequests; // Maps arbitration ID to its data. arbitrationRequests[uint(questionID)][requester].
    uint256 public templateId; // The dispute template identifier.
    mapping(uint256 => DisputeDetails) public disputeIDToDisputeDetails; // Maps external dispute ids to local arbitration ID and requester who was able to complete the arbitration request.
    mapping(uint256 => bool) public arbitrationIDToDisputeExists; // Whether a dispute has already been created for the given arbitration ID or not.
    mapping(uint256 => address) public arbitrationIDToRequester; // Maps arbitration ID to the requester who was able to complete the arbitration request.
    mapping(uint256 => uint256) public arbitrationCreatedBlock; // Block of dispute creation. arbitrationCreatedBlock[disputeID]

    /**
     * @notice Creates an arbitration proxy on the foreign chain.
     * @param _wNative The address of the wrapped version of the native currency.
     * @param _arbitrator Arbitrator contract address.
     * @param _arbitratorExtraData The extra data used to raise a dispute in the arbitrator.
     * @param _templateRegistry The dispute template registry.
     * @param _templateData The dispute template data.
     * @param _templateDataMappings The dispute template data mappings.
     * @param _homeEid The endpoint ID where the home proxy is deployed.
     * @param _endpoint The LayerZero endpoint address.
     */
    constructor(
        address _wNative,
        IArbitratorV2 _arbitrator,
        bytes memory _arbitratorExtraData,
        IDisputeTemplateRegistry _templateRegistry,
        string memory _templateData,
        string memory _templateDataMappings,
        uint32 _homeEid,
        address _endpoint
    ) OApp(_endpoint, msg.sender) Ownable(msg.sender) {
        wNative = _wNative;
        arbitrator = _arbitrator;
        arbitratorExtraData = _arbitratorExtraData;
        templateRegistry = _templateRegistry;
        templateId = _templateRegistry.setDisputeTemplate(
            "",
            _templateData,
            _templateDataMappings
        );
        homeEid = _homeEid;
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
     * @notice Allows the owner to change the dispute template.
     * @param _templateData The new dispute template data.
     * @param _templateDataMappings The new dispute template data mappings.
     */
    function changeDisputeTemplate(
        string memory _templateData,
        string memory _templateDataMappings
    ) external onlyOwner {
        templateId = templateRegistry.setDisputeTemplate(
            "",
            _templateData,
            _templateDataMappings
        );
    }

    /* External and public */

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

        try this._decodeMessage(_message) returns (
            uint16 _msgType,
            bytes memory _payload
        ) {
            msgType = _msgType;
            payload = _payload;
        } catch {
            revert("Invalid message format");
        }

        // Route message based on type
        if (msgType == MSG_TYPE_ARBITRATION_ACKNOWLEDGEMENT) {
            try this._decodeArbitrationAcknowledgement(payload) returns (
                bytes32 questionID,
                address requester
            ) {
                _handleArbitrationAcknowledgement(questionID, requester);
            } catch {
                revert("Invalid arbitration acknowledgement payload");
            }
        } else if (msgType == MSG_TYPE_ARBITRATION_CANCELATION) {
            try this._decodeArbitrationCancelation(payload) returns (
                bytes32 questionID,
                address requester
            ) {
                _handleArbitrationCancelation(questionID, requester);
            } catch {
                revert("Invalid arbitration cancelation payload");
            }
        } else {
            revert("Unknown message type");
        }
    }

    /**
     * @notice External decoder functions for safe message parsing.
     * @dev These are marked external to be called via try/catch for error handling.
     */
    function _decodeMessage(
        bytes calldata _message
    ) external pure returns (uint16 msgType, bytes memory payload) {
        return abi.decode(_message, (uint16, bytes));
    }

    function _decodeArbitrationAcknowledgement(
        bytes memory _payload
    ) external pure returns (bytes32 questionID, address requester) {
        return abi.decode(_payload, (bytes32, address));
    }

    function _decodeArbitrationCancelation(
        bytes memory _payload
    ) external pure returns (bytes32 questionID, address requester) {
        return abi.decode(_payload, (bytes32, address));
    }

    // ************************ //
    // *    Realitio logic    * //
    // ************************ //

    /**
     * @notice Requests arbitration for the given question and contested answer.
     * This version of the function uses recommended bridging parameters.
     * Note that the signature of this function can't be changed as it's required by Reality UI.
     * @param _questionID The ID of the question.
     * @param _maxPrevious The maximum value of the current bond for the question. The arbitration request will get rejected if the current bond is greater than _maxPrevious. If set to 0, _maxPrevious is ignored.
     */
    function requestArbitration(
        bytes32 _questionID,
        uint256 _maxPrevious
    ) external payable override {
        _requestArbitration(_questionID, _maxPrevious);
    }

    /**
     * @notice Requests arbitration for the given question and contested answer.
     * This function is to be used if the bridging with default parameters fail.
     * @param _questionID The ID of the question.
     * @param _maxPrevious The maximum value of the current bond for the question. The arbitration request will get rejected if the current bond is greater than _maxPrevious. If set to 0, _maxPrevious is ignored.
     * @param _options LayerZero message execution options.
     */
    function requestArbitrationCustomParameters(
        bytes32 _questionID,
        uint256 _maxPrevious,
        bytes calldata _options
    ) external payable {
        _requestArbitration(_questionID, _maxPrevious, _options);
    }

    /**
     * @notice Receives the acknowledgement of the arbitration request for the given question and requester. TRUSTED.
     * @param _questionID The ID of the question.
     * @param _requester The requester.
     */
    function receiveArbitrationAcknowledgement(
        bytes32 _questionID,
        address _requester
    ) external override {
        _handleArbitrationAcknowledgement(_questionID, _requester);
    }

    /**
     * @dev Internal handler for arbitration acknowledgements.
     */
    function _handleArbitrationAcknowledgement(
        bytes32 _questionID,
        address _requester
    ) internal {
        require(_questionID != bytes32(0), "Question ID cannot be empty");
        require(_requester != address(0), "Requester cannot be zero address");

        uint256 arbitrationID = uint256(_questionID);
        ArbitrationRequest storage arbitration = arbitrationRequests[
            arbitrationID
        ][_requester];
        require(
            arbitration.status == Status.Requested,
            "Invalid arbitration status"
        );

        // Arbitration cost can possibly change between when the request has been made and received, so evaluate once more.
        uint256 arbitrationCost = arbitrator.arbitrationCost(
            arbitratorExtraData
        );

        if (arbitration.deposit >= arbitrationCost) {
            try
                arbitrator.createDispute{value: arbitrationCost}(
                    NUMBER_OF_CHOICES_FOR_ARBITRATOR,
                    arbitratorExtraData
                )
            returns (uint256 disputeID) {
                DisputeDetails
                    storage disputeDetails = disputeIDToDisputeDetails[
                        disputeID
                    ];
                disputeDetails.arbitrationID = arbitrationID;
                disputeDetails.requester = _requester;

                arbitrationIDToDisputeExists[arbitrationID] = true;
                arbitrationIDToRequester[arbitrationID] = _requester;
                arbitrationCreatedBlock[disputeID] = block.number;

                // At this point, arbitration.deposit is guaranteed to be greater than or equal to the arbitration cost.
                uint256 remainder = arbitration.deposit - arbitrationCost;

                arbitration.status = Status.Created;
                arbitration.deposit = 0;
                arbitration.disputeID = disputeID;

                if (remainder > 0) {
                    payable(_requester).safeSend(remainder, wNative);
                }

                emit ArbitrationCreated(_questionID, _requester, disputeID);
                emit DisputeRequest(
                    arbitrator,
                    disputeID,
                    arbitrationID,
                    templateId,
                    ""
                );
            } catch {
                arbitration.status = Status.Failed;
                emit ArbitrationFailed(_questionID, _requester);
            }
        } else {
            arbitration.status = Status.Failed;
            emit ArbitrationFailed(_questionID, _requester);
        }
    }

    /**
     * @notice Receives the cancelation of the arbitration request for the given question and requester. TRUSTED.
     * @param _questionID The ID of the question.
     * @param _requester The requester.
     */
    function receiveArbitrationCancelation(
        bytes32 _questionID,
        address _requester
    ) external override {
        _handleArbitrationCancelation(_questionID, _requester);
    }

    /**
     * @dev Internal handler for arbitration cancelations.
     */
    function _handleArbitrationCancelation(
        bytes32 _questionID,
        address _requester
    ) internal {
        require(_questionID != bytes32(0), "Question ID cannot be empty");
        require(_requester != address(0), "Requester cannot be zero address");

        uint256 arbitrationID = uint256(_questionID);
        ArbitrationRequest storage arbitration = arbitrationRequests[
            arbitrationID
        ][_requester];
        require(
            arbitration.status == Status.Requested,
            "Invalid arbitration status"
        );
        uint256 deposit = arbitration.deposit;

        delete arbitrationRequests[arbitrationID][_requester];
        payable(_requester).safeSend(deposit, wNative);

        emit ArbitrationCanceled(_questionID, _requester);
    }

    /**
     * @notice Cancels the arbitration in case the dispute could not be created.
     * This version of the function uses recommended bridging parameters.
     * @param _questionID The ID of the question.
     * @param _requester The address of the arbitration requester.
     */
    function handleFailedDisputeCreation(
        bytes32 _questionID,
        address _requester
    ) external override {
        _handleFailedDisputeCreation(_questionID, _requester);
    }

    /**
     * @notice Cancels the arbitration in case the dispute could not be created.
     * This function is to be used if the bridging with default parameters fail.
     * @param _questionID The ID of the question.
     * @param _requester The address of the arbitration requester.
     * @param _options LayerZero message execution options.
     */
    function handleFailedDisputeCreationCustomParameters(
        bytes32 _questionID,
        address _requester,
        bytes calldata _options
    ) external {
        _handleFailedDisputeCreation(_questionID, _requester, _options);
    }

    /**
     * @notice Rules a specified dispute. Can only be called by the arbitrator.
     * @param _disputeID The ID of the dispute in the arbitrator.
     * @param _ruling The ruling given by the arbitrator.
     */
    function rule(uint256 _disputeID, uint256 _ruling) external override {
        DisputeDetails storage disputeDetails = disputeIDToDisputeDetails[
            _disputeID
        ];
        uint256 arbitrationID = disputeDetails.arbitrationID;
        address requester = disputeDetails.requester;

        ArbitrationRequest storage arbitration = arbitrationRequests[
            arbitrationID
        ][requester];
        require(msg.sender == address(arbitrator), "Only arbitrator allowed");
        require(
            arbitration.status == Status.Created,
            "Invalid arbitration status"
        );

        arbitration.answer = _ruling;
        arbitration.status = Status.Ruled;

        emit Ruling(arbitrator, _disputeID, _ruling);
    }

    /**
     * @notice Relays the ruling to home proxy.
     * This version of the function uses recommended bridging parameters.
     * @param _questionID The ID of the question.
     * @param _requester The address of the arbitration requester.
     */
    function relayRule(bytes32 _questionID, address _requester) external {
        _relayRule(_questionID, _requester);
    }

    /**
     * @notice Relays the ruling to home proxy.
     * This function is to be used if the bridging with default parameters fail.
     * @param _questionID The ID of the question.
     * @param _requester The address of the arbitration requester.
     * @param _options LayerZero message execution options.
     */
    function relayRuleCustomParameters(
        bytes32 _questionID,
        address _requester,
        bytes calldata _options
    ) external {
        _relayRule(_questionID, _requester, _options);
    }

    /* External Views */

    /**
     * @notice Returns number of possible ruling options. Valid rulings are [0, return value].
     * @return count The number of ruling options.
     */
    function numberOfRulingOptions(
        uint256 /* _arbitrationID */
    ) external pure returns (uint256) {
        return NUMBER_OF_CHOICES_FOR_ARBITRATOR;
    }

    /**
     * @notice Gets the fee to create a dispute.
     * @return The fee to create a dispute.
     */
    function getDisputeFee(
        bytes32 /* _questionID */
    ) external view override returns (uint256) {
        return arbitrator.arbitrationCost(arbitratorExtraData);
    }

    /**
     * @notice Casts question ID into uint256 thus returning the related arbitration ID.
     * @param _questionID The ID of the question.
     * @return The ID of the arbitration.
     */
    function questionIDToArbitrationID(
        bytes32 _questionID
    ) external pure returns (uint256) {
        return uint256(_questionID);
    }

    /**
     * @notice Maps external (arbitrator side) dispute id to local (arbitrable) dispute id.
     * @param _externalDisputeID Dispute id as in arbitrator side.
     * @return localDisputeID Dispute id as in arbitrable contract.
     */
    function externalIDtoLocalID(
        uint256 _externalDisputeID
    ) external view returns (uint256) {
        return disputeIDToDisputeDetails[_externalDisputeID].arbitrationID;
    }

    // **************************** //
    // *         Internal         * //
    // **************************** //

    function _requestArbitration(
        bytes32 _questionID,
        uint256 _maxPrevious
    ) internal {
        bytes memory gasOptions = abi.encodePacked(uint16(1), uint128(300000)); // Set gas limit to 300,000 for arbitration request processing
        _requestArbitration(_questionID, _maxPrevious, gasOptions);
    }

    function _requestArbitration(
        bytes32 _questionID,
        uint256 _maxPrevious,
        bytes memory _options
    ) internal {
        require(
            !arbitrationIDToDisputeExists[uint256(_questionID)],
            "Dispute already created"
        );

        ArbitrationRequest storage arbitration = arbitrationRequests[
            uint256(_questionID)
        ][msg.sender];
        require(
            arbitration.status == Status.None,
            "Arbitration already requested"
        );

        uint256 arbitrationCost = arbitrator.arbitrationCost(
            arbitratorExtraData
        );

        // LayerZero fee calculation
        bytes memory message = abi.encode(
            MSG_TYPE_ARBITRATION_REQUEST,
            _questionID,
            msg.sender,
            _maxPrevious
        );
        bytes memory combinedOptions = this.combineOptions(
            homeEid,
            MSG_TYPE_ARBITRATION_REQUEST,
            _options
        );
        MessagingFee memory lzFee = _quote(
            homeEid,
            message,
            combinedOptions,
            false
        );

        // Only require arbitration cost from msg.sender - LayerZero fee comes from contract balance
        require(msg.value >= arbitrationCost, "Insufficient arbitration fee");
        require(
            address(this).balance >= lzFee.nativeFee,
            "Insufficient contract balance for LayerZero fee"
        );

        arbitration.status = Status.Requested;
        arbitration.deposit = uint248(msg.value); // Store full deposit for arbitration

        _lzSend(
            homeEid,
            message,
            combinedOptions,
            MessagingFee(lzFee.nativeFee, 0),
            payable(address(this))
        );

        emit ArbitrationRequested(_questionID, msg.sender, _maxPrevious);
    }

    function _handleFailedDisputeCreation(
        bytes32 _questionID,
        address _requester
    ) internal {
        bytes memory gasOptions = abi.encodePacked(uint16(1), uint128(200000)); // Set gas limit to 200,000 for arbitration failure processing
        _handleFailedDisputeCreation(_questionID, _requester, gasOptions);
    }

    function _handleFailedDisputeCreation(
        bytes32 _questionID,
        address _requester,
        bytes memory _options
    ) internal {
        uint256 arbitrationID = uint256(_questionID);
        ArbitrationRequest storage arbitration = arbitrationRequests[
            arbitrationID
        ][_requester];
        require(
            arbitration.status == Status.Failed,
            "Invalid arbitration status"
        );
        uint256 deposit = arbitration.deposit;

        // LayerZero fee calculation
        bytes memory message = abi.encode(
            MSG_TYPE_ARBITRATION_FAILURE,
            _questionID,
            _requester
        );
        bytes memory combinedOptions = this.combineOptions(
            homeEid,
            MSG_TYPE_ARBITRATION_FAILURE,
            _options
        );
        MessagingFee memory lzFee = _quote(
            homeEid,
            message,
            combinedOptions,
            false
        );

        // Check contract balance for LayerZero fee
        if (address(this).balance < lzFee.nativeFee) {
            revert InsufficientFundsForLayerZero(
                lzFee.nativeFee,
                address(this).balance
            );
        }

        // Note that we don't nullify the status to allow the function to be called
        // multiple times to avoid intentional blocking.
        // Also note that since the status is not nullified the requester must use a different address
        // to make a new request for the same question.
        arbitration.deposit = 0;
        payable(_requester).safeSend(deposit, wNative);

        _lzSend(
            homeEid,
            message,
            combinedOptions,
            MessagingFee(lzFee.nativeFee, 0),
            payable(address(this))
        );

        emit ArbitrationCanceled(_questionID, _requester);
    }

    function _relayRule(bytes32 _questionID, address _requester) internal {
        bytes memory gasOptions = abi.encodePacked(uint16(1), uint128(250000)); // Set gas limit to 250,000 for arbitration answer processing
        _relayRule(_questionID, _requester, gasOptions);
    }

    function _relayRule(
        bytes32 _questionID,
        address _requester,
        bytes memory _options
    ) internal {
        uint256 arbitrationID = uint256(_questionID);
        ArbitrationRequest storage arbitration = arbitrationRequests[
            arbitrationID
        ][_requester];
        // Note that we allow to relay multiple times to prevent intentional blocking.
        require(
            arbitration.status == Status.Ruled ||
                arbitration.status == Status.Relayed,
            "Dispute not resolved"
        );

        arbitration.status = Status.Relayed;

        // Realitio ruling is shifted by 1 compared to Kleros.
        uint256 realitioRuling = arbitration.answer != 0
            ? arbitration.answer - 1
            : REFUSE_TO_ARBITRATE_REALITIO;

        bytes memory message = abi.encode(
            MSG_TYPE_ARBITRATION_ANSWER,
            _questionID,
            bytes32(realitioRuling)
        );

        // LayerZero fee calculation
        bytes memory combinedOptions = this.combineOptions(
            homeEid,
            MSG_TYPE_ARBITRATION_ANSWER,
            _options
        );
        MessagingFee memory lzFee = _quote(
            homeEid,
            message,
            combinedOptions,
            false
        );

        // Check contract balance for LayerZero fee
        if (address(this).balance < lzFee.nativeFee) {
            revert InsufficientFundsForLayerZero(
                lzFee.nativeFee,
                address(this).balance
            );
        }

        _lzSend(
            homeEid,
            message,
            combinedOptions,
            MessagingFee(lzFee.nativeFee, 0),
            payable(address(this))
        );

        emit RulingRelayed(_questionID, bytes32(realitioRuling));
    }
}
