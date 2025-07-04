# Kleros v2 Upgrade Plan for LayerZero Contracts

## Overview

This plan outlines the steps needed to upgrade `RealitioForeignProxyLZ.sol` and `RealitioHomeProxyLZ.sol` from Kleros v1 to Kleros v2. The upgrade involves significant changes to interfaces, dispute creation, and removes the complex appeal/evidence system that was handled in v1.

## Key Differences Between v1 and v2

### 1. Interface Changes
- **v1**: `IArbitrator` → **v2**: `IArbitratorV2`
- **v1**: `IArbitrable` → **v2**: `IArbitrableV2`
- **v1**: `IDisputeResolver` → **v2**: No longer exists

### 2. Appeal System
- **v1**: Appeals handled by arbitrator interface (`appealCost`, `appealPeriod`, `appeal` functions)
- **v2**: Appeals handled by DisputeKit implementation, removed from arbitrator interface

### 3. Dispute Creation
- **v1**: `createDispute(uint256 _choices, bytes calldata _extraData)`
- **v2**: `createDispute(uint256 _numberOfChoices, bytes calldata _extraData)`

### 4. Ruling System
- **v1**: `currentRuling(uint256 _disputeID) returns (uint256 ruling)`
- **v2**: `currentRuling(uint256 _disputeID) returns (uint256 ruling, bool tied, bool overridden)`

### 5. Evidence/MetaEvidence
- **v1**: Uses `MetaEvidence` events and evidence submission
- **v2**: Uses dispute templates via `IDisputeTemplateRegistry`

### 6. Events
- **v1**: `MetaEvidence`, `Evidence`, `Dispute` events
- **v2**: `DisputeRequest` event

## Implementation Plan

### Phase 1: Interface Updates

#### 1.1 Update RealitioForeignProxyLZ.sol

**Import Changes:**
- Remove: `import {IDisputeResolver, IArbitrator} from "@kleros/dispute-resolver-interface-contract-0.8/contracts/IDisputeResolver.sol";`
- Add: `import {IArbitrableV2, IArbitratorV2} from "@kleros/kleros-v2-contracts/arbitration/interfaces/IArbitratorV2.sol";`
- Add: `import {IDisputeTemplateRegistry} from "@kleros/kleros-v2-contracts/arbitration/interfaces/IDisputeTemplateRegistry.sol";`

**Contract Declaration:**
- Change: `contract RealitioForeignProxyLZ is IForeignArbitrationProxy, IDisputeResolver`
- To: `contract RealitioForeignProxyLZ is IForeignArbitrationProxy, IArbitrableV2`

**Storage Variables:**
- Change: `IArbitrator public immutable arbitrator;`
- To: `IArbitratorV2 public immutable arbitrator;`
- Add: `IDisputeTemplateRegistry public immutable templateRegistry;`
- Add: `uint256 public immutable templateId;`

#### 1.2 Update RealitioHomeProxyLZ.sol

**No major interface changes needed** - this contract doesn't interact directly with Kleros arbitrator.

### Phase 2: Remove Appeal System

#### 2.1 Remove Appeal-Related Code from RealitioForeignProxyLZ.sol

**Remove Functions:**
- `fundAppeal()`
- `withdrawFeesAndRewards()`
- `withdrawFeesAndRewardsForAllRounds()`
- `getMultipliers()`
- `getNumberOfRounds()`
- `getRoundInfo()`
- `getFundingStatus()`
- `getContributionsToSuccessfulFundings()`
- `getTotalWithdrawableAmount()`

**Remove Storage:**
- `Round` struct
- `rounds` array in `ArbitrationRequest`
- `winnerMultiplier`, `loserMultiplier`, `loserAppealPeriodMultiplier`
- All round-related mappings

**Remove Events:**
- `Contribution`
- `RulingFunded`
- `Withdrawal`

#### 2.2 Simplify ArbitrationRequest Struct

**Current:**
```solidity
struct ArbitrationRequest {
    Status status;
    uint248 deposit;
    uint256 disputeID;
    uint256 answer;
    Round[] rounds;
}
```

**New:**
```solidity
struct ArbitrationRequest {
    Status status;
    uint248 deposit;
    uint256 disputeID;
    uint256 answer;
    uint256 templateId; // For dispute template
}
```

### Phase 3: Update Dispute Creation

#### 3.1 Update Constructor

**Add Parameters:**
- `IDisputeTemplateRegistry _templateRegistry`
- `string memory _templateData`
- `string memory _templateDataMappings`

**Remove Parameters:**
- `string memory _metaEvidence`
- `uint256 _winnerMultiplier`
- `uint256 _loserMultiplier`
- `uint256 _loserAppealPeriodMultiplier`

#### 3.2 Update receiveArbitrationAcknowledgement()

**Current Dispute Creation:**
```solidity
arbitrator.createDispute{value: arbitrationCost}(NUMBER_OF_CHOICES_FOR_ARBITRATOR, arbitratorExtraData)
```

**New Dispute Creation:**
```solidity
arbitrator.createDispute{value: arbitrationCost}(NUMBER_OF_CHOICES_FOR_ARBITRATOR, arbitratorExtraData)
```

**Add Template Event:**
```solidity
emit DisputeRequest(arbitrator, disputeID, arbitrationID, templateId, "");
```

### Phase 4: Update Evidence System

#### 4.1 Remove Evidence Functions

**Remove from RealitioForeignProxyLZ.sol:**
- `submitEvidence()` function
- `Evidence` event emission

#### 4.2 Update MetaEvidence System

**Remove:**
- `MetaEvidence` event emission in constructor
- `META_EVIDENCE_ID` constant

**Add:**
- Template registration in constructor
- `DisputeRequest` event emission

### Phase 5: Update Ruling System

#### 5.1 Update rule() Function

**Current:**
```solidity
function rule(uint256 _disputeID, uint256 _ruling) external override
```

**Changes:**
- Remove appeal-related logic
- Remove round handling
- Simplify ruling assignment
- Remove `Ruling` event (handled by arbitrator in v2)

#### 5.2 Update currentRuling Usage

**Update any calls to:**
- `arbitrator.currentRuling(_disputeID)` → handle new return values `(ruling, tied, overridden)`

### Phase 6: Update Utility Functions

#### 6.1 Update View Functions

**Remove:**
- All appeal-related view functions
- `numberOfRulingOptions()` (may need to keep for interface compatibility)

**Update:**
- `getDisputeFee()` to use v2 interface

#### 6.2 Update Event Emissions

**Replace:**
- `MetaEvidence` events with `DisputeRequest` events
- Remove `Evidence` event emissions

### Phase 7: Testing and Validation

#### 7.1 Create Test Suite

**Test Cases:**
1. Dispute creation with v2 arbitrator
2. Cross-chain communication (Home ↔ Foreign)
3. Ruling relay functionality
4. Template registration and usage
5. Fee calculation accuracy

#### 7.2 Integration Testing

**Test with:**
- Kleros v2 testnet deployment
- LayerZero testnet
- Realitio testnet contract

### Phase 8: Documentation and Deployment

#### 8.1 Update Documentation

**Update:**
- Contract interfaces documentation
- Deployment scripts
- Integration guides

#### 8.2 Deployment Strategy

**Steps:**
1. Deploy v2 contracts to testnet
2. Comprehensive testing
3. Security review
4. Mainnet deployment
5. Migration plan from v1 to v2

## Files to Modify

### Primary Contracts
- `contracts/src/RealitioForeignProxyLZ.sol` - Major changes
- `contracts/src/RealitioHomeProxyLZ.sol` - Minor changes

### Supporting Files
- `contracts/src/interfaces/IArbitrationProxies.sol` - Update interfaces
- Deployment scripts
- Test files

## Compatibility Notes

### Breaking Changes
- **Appeal System**: Complete removal of appeal functionality
- **Evidence System**: Removal of evidence submission
- **Events**: Different event structure
- **View Functions**: Many appeal-related functions removed

### Backward Compatibility
- **Not backward compatible** with v1 arbitrator
- **Requires** Kleros v2 deployment
- **Interface changes** will break existing integrations

## Implementation Timeline

1. **Week 1-2**: Interface updates and basic structure changes
2. **Week 3**: Remove appeal system and update dispute creation
3. **Week 4**: Update evidence/template system and ruling logic
4. **Week 5**: Testing and debugging
5. **Week 6**: Integration testing and documentation
6. **Week 7**: Security review and final adjustments
7. **Week 8**: Deployment preparation and execution

## Risk Mitigation

### Technical Risks
- **Interface mismatches**: Thorough testing with v2 arbitrator
- **Cross-chain compatibility**: Extensive LayerZero integration testing
- **Gas optimization**: Profile gas usage vs v1 implementation

### Operational Risks
- **Migration complexity**: Develop clear migration guide
- **User adoption**: Ensure clear communication about changes
- **Downtime**: Plan for smooth transition from v1 to v2

## Success Criteria

- [ ] All tests pass with Kleros v2 arbitrator
- [ ] Cross-chain dispute creation and resolution works
- [ ] Gas costs are reasonable compared to v1
- [ ] All existing Realitio integration points work
- [ ] Security audit completed successfully
- [ ] Documentation is complete and accurate 