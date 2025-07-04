# Kleros v2 Upgrade Plan for LayerZero Proxy Contracts

## Overview
Upgrade `RealitioForeignProxyLZ.sol` and `RealitioHomeProxyLZ.sol` to support Kleros v2 arbitration while maintaining cross-chain functionality via LayerZero.

## Key Differences: Kleros v1 vs v2

### Interface Changes
- **v1**: Uses `IArbitrator` and `IDisputeResolver`
- **v2**: Uses `IArbitratorV2` and `IArbitrableV2`

### New Components in v2
- **EvidenceModule**: Handles evidence submission and management
- **IDisputeTemplateRegistry**: Manages dispute templates for structured dispute data
- **Enhanced Parameter Management**: More sophisticated arbitration parameter handling

### Method Signature Changes
- **v1**: `createDispute(uint256 _choices, bytes _extraData)`
- **v2**: `createDispute(uint256 _numberOfChoices, bytes _extraData)`

## Contract-by-Contract Upgrade Plan

### 1. RealitioForeignProxyLZ.sol Upgrades

#### 1.1 Interface Updates
- [ ] Replace `IArbitrator` with `IArbitratorV2`
- [ ] Replace `IDisputeResolver` with `IArbitrableV2`
- [ ] Import `EvidenceModule` from Kleros v2 contracts
- [ ] Import `IDisputeTemplateRegistry` from Kleros v2 contracts

#### 1.2 Storage Updates
- [ ] Add `EvidenceModule public evidenceModule`
- [ ] Add `IDisputeTemplateRegistry public templateRegistry`
- [ ] Add `uint256 public templateId`
- [ ] Add `ArbitrationParams` struct similar to RealityV2.sol
- [ ] Add `arbitrationParamsChanges` array for parameter versioning

#### 1.3 Constructor Updates
- [ ] Add `EvidenceModule _evidenceModule` parameter
- [ ] Add `IDisputeTemplateRegistry _templateRegistry` parameter
- [ ] Add `string memory _templateData` parameter
- [ ] Add `string memory _templateDataMappings` parameter
- [ ] Initialize dispute template in constructor

#### 1.4 Method Updates
- [ ] Update `createDispute` call to use v2 interface
- [ ] Add `rule` method implementation for `IArbitrableV2`
- [ ] Update dispute creation to emit `DisputeRequest` event
- [ ] Add evidence submission methods if needed

#### 1.5 Governance Methods
- [ ] Add `changeArbitrationParams` method
- [ ] Add `changeTemplateRegistry` method
- [ ] Add `changeDisputeTemplate` method
- [ ] Add appropriate access control (governor pattern)

### 2. RealitioHomeProxyLZ.sol Upgrades

#### 2.1 Interface Updates
- [ ] Update imports to reference v2 interfaces where needed
- [ ] Ensure compatibility with v2 arbitration flow

#### 2.2 Message Protocol Updates
- [ ] Review cross-chain message format compatibility
- [ ] Update message handlers to support v2 dispute data
- [ ] Add support for evidence module interactions if needed

#### 2.3 Storage Updates
- [ ] Add fields to track v2-specific arbitration parameters
- [ ] Update `Request` struct if needed for v2 compatibility

### 3. Cross-Chain Communication Updates

#### 3.1 Message Format Review
- [ ] Ensure LayerZero message payloads support v2 data structures
- [ ] Update message tags if new message types are needed
- [ ] Verify backward compatibility during transition period

#### 3.2 Evidence Handling
- [ ] Determine if evidence needs to be bridged cross-chain
- [ ] Implement evidence relay mechanism if required
- [ ] Add evidence-related message types to LayerZero protocol

### 4. Error Handling and Events

#### 4.1 Error Updates
- [ ] Replace old error patterns with v2-style custom errors
- [ ] Add new error types for v2-specific conditions
- [ ] Update error messages for clarity

#### 4.2 Event Updates
- [ ] Add `DisputeRequest` event emission
- [ ] Add `Ruling` event emission
- [ ] Update existing events for v2 compatibility

### 5. Testing and Validation

#### 5.1 Unit Tests
- [ ] Test v2 dispute creation flow
- [ ] Test cross-chain message handling
- [ ] Test evidence submission (if implemented)
- [ ] Test governance functions

#### 5.2 Integration Tests
- [ ] Test full cross-chain arbitration flow
- [ ] Test dispute resolution and ruling relay
- [ ] Test appeal mechanism (if applicable)

#### 5.3 Migration Tests
- [ ] Test upgrade path from v1 to v2
- [ ] Test backward compatibility scenarios
- [ ] Test parameter migration

### 6. Documentation Updates

#### 6.1 Technical Documentation
- [ ] Update contract documentation
- [ ] Document new v2-specific features
- [ ] Update deployment guides

#### 6.2 API Documentation
- [ ] Update method signatures in documentation
- [ ] Document new governance methods
- [ ] Update error handling documentation

## Implementation Priority

### Phase 1: Core Upgrade (High Priority)
1. Interface and import updates
2. Basic v2 dispute creation
3. Core arbitration flow compatibility

### Phase 2: Advanced Features (Medium Priority)
1. Evidence module integration
2. Dispute template management
3. Enhanced governance functions

### Phase 3: Optimization (Low Priority)
1. Gas optimization
2. Advanced error handling
3. Extended testing coverage

## Risk Assessment

### High Risk Items
- Cross-chain message format changes
- Arbitration parameter migration
- Evidence handling complexity

### Medium Risk Items
- Event emission changes
- Error handling updates
- Template registry integration

### Low Risk Items
- Documentation updates
- Gas optimization
- Extended testing

## Success Criteria

1. **Functional Compatibility**: All v2 arbitration features work correctly
2. **Cross-Chain Integrity**: LayerZero bridging remains secure and functional
3. **Backward Compatibility**: Smooth migration path from v1 to v2
4. **Gas Efficiency**: No significant gas cost increases
5. **Security**: All security properties maintained or improved

## Timeline Estimate

- **Phase 1**: 2-3 weeks
- **Phase 2**: 1-2 weeks  
- **Phase 3**: 1 week
- **Total**: 4-6 weeks

## Notes

- Consider maintaining v1 compatibility during transition period
- Ensure proper access control for all governance functions
- Test thoroughly on testnets before mainnet deployment
- Consider implementing upgrade mechanisms for future versions 