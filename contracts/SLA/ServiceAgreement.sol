pragma solidity 0.4.25;

/**
@title Ocean Protocol Service Level Agreement
@author Team: Ahmed Ali, Samer Sallam
*/

contract ServiceAgreement {

    struct ServiceAgreementTemplate {
        bool state; // 1 -> Available 0 -> revoked template
        address owner; // template owner
        bytes32[] conditionKeys; // preserving the order in the condition state
        uint256[] dependenciesBits; // 1st bit --> dependency, 2nd bit --> timeout flag (enabled/disabled)
    }
    // conditions id (templateId, contract address , function fingerprint)
    // it maps condition id to dependencies [uint256 is a compressed version]
    mapping(bytes32 => uint256) conditionKeyToIndex;

    struct Agreement {
        bool state; // instance of SLA status
        uint8[] conditionsState; // maps the condition status in the template
        uint8[] conditionLockedState; // maps the condition status in the template
        bytes32 templateId; // referes to SLA template id
        address consumer;
        // condition Instance = [handler + value hash]
        bytes32[] conditionInstances;
        uint256[] timeoutValues; // in terms of block number not sec!
        bytes32 serviceDefinition;
        bytes32 DID;
    }

    mapping(bytes32 => ServiceAgreementTemplate) templates;
    // instances of SLA template
    mapping(bytes32 => Agreement) agreements;

    // map template Id to a list of agreement instances
    mapping(bytes32 => bytes32[]) templateId2Agreements;

    // is able to revoke agreement template (template is no longer accessible)
    modifier canRevokeTemplate(bytes32 templateId){
        for (uint256 i = 0; i < templateId2Agreements[templateId].length; i++) {
            require(agreements[templateId2Agreements[templateId][i]].state == true, 'Owner can not revoke template!');
        }
        _;
    }

    // check if the no longer pending unfulfilled conditions in the SLA
    modifier noPendingFulfillments(bytes32 serviceId){
        for (uint256 i = 0; i < agreements[serviceId].conditionsState.length; i++) {
            require(agreements[serviceId].conditionsState[i] == 1, 'Not able to fulfill service agreement instance');
        }
        _;
    }

    // check if the controller contract is authorized to change the condition state
    modifier isValidControllerHandler(bytes32 serviceId, bytes4 fingerprint, bytes32 valueHash) {
        bytes32 conditionKey = getConditionByFingerprint(serviceId, msg.sender, fingerprint);
        require(
            agreements[serviceId].conditionInstances[conditionKeyToIndex[conditionKey]] ==
            keccak256(abi.encodePacked(conditionKey, valueHash)),
            'unable to reconstruct the right condition hash'
        );
        require(agreements[serviceId].conditionLockedState[conditionKeyToIndex[conditionKey]] == 0, 'This condition is locked, access denied.');
        require(!hasUnfulfilledDependencies(serviceId, conditionKey), 'This condition has unfulfilled dependency');
        _;
    }

    // is the sender authorized to create instance of the SLA template
    modifier isOwner(bytes32 templateId){
        require(templates[templateId].owner == msg.sender, 'Not a template owner');
        _;
    }

    // events
    event SetupCondition(bytes32 serviceTemplate, bytes32 condition, address provider);
    event SetupAgreementTemplate(bytes32 serviceTemplateId, address provider);
    event ExecuteCondition(bytes32 serviceId, bytes32 condition, bool status, address templateOwner, address consumer);
    event ExecuteAgreement(bytes32 serviceId, bytes32 templateId, bool status, address templateOwner, address consumer, bool state);
    event ConditionFulfilled(bytes32 serviceId, bytes32 templateId, bytes32 condition);
    event AgreementFulfilled(bytes32 serviceId, bytes32 templateId, address owner);
    event SLATemplateRevoked(bytes32 templateId, bool state);

    // temp events
    event PrefixedHash(bytes32 hash, bool status, bytes32 sid);

    // Setup service agreement template only once!
    function setupAgreementTemplate(address[] contracts, bytes4[] fingerprints, uint256[] dependenciesBits, bytes32 service)
    public returns (bool){
        // TODO: whitelisting the contracts/fingerprints
        require(contracts.length == fingerprints.length, 'fingerprints and contracts length do not match');
        require(contracts.length == dependenciesBits.length, 'contracts and dependencies do not match');
        // 1. generate service ID
        bytes32 templateId = keccak256(abi.encodePacked(msg.sender, service, dependenciesBits.length, contracts.length));
        // 2. generate conditions
        templates[templateId] = ServiceAgreementTemplate(true, msg.sender, new bytes32[](0), dependenciesBits);
        for (uint256 i = 0; i < contracts.length; i++) {
            templates[templateId].conditionKeys.push(keccak256(abi.encodePacked(templateId, contracts[i], fingerprints[i])));
            conditionKeyToIndex[keccak256(abi.encodePacked(templateId, contracts[i], fingerprints[i]))] = i;
            emit SetupCondition(templateId, keccak256(abi.encodePacked(templateId, contracts[i], fingerprints[i])), msg.sender);
        }
        emit SetupAgreementTemplate(templateId, msg.sender);
        return true;
    }

    function isValidSignature(bytes32 hash, bytes signature, address consumer) private pure returns (bool){
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);
        return (consumer == ecrecover(hash, v, r, s));
    }

    function generatePrefixHash(bytes32 hash) private pure returns (bytes32 prefixedHash) {
        bytes memory prefix = '\x19Ethereum Signed Message:\n32';
        return keccak256(abi.encodePacked(prefix, hash));
    }

    function executeAgreement(bytes32 templateId, bytes signature, address consumer, bytes32[] valueHash, uint256[] timeoutValues, bytes32 serviceDefinition, bytes32 did) public
    isOwner(templateId) returns (bool) {
        require(timeoutValues.length == templates[templateId].conditionKeys.length, 'invalid timeout values length');
        ServiceAgreementTemplate storage slaTemplate = templates[templateId];
        require(slaTemplate.state == true, 'Template is revoked');
        // reconstruct the agreement fingerprint and check the consumer signature
        bytes32 prefixedHash = generatePrefixHash(keccak256(abi.encodePacked(templateId, slaTemplate.conditionKeys, valueHash, timeoutValues, serviceDefinition, did)));

        bytes32 serviceAgreementId = keccak256(abi.encodePacked(templateId, consumer, block.number, prefixedHash));

        // verify consumer's signature and trigger the execution of agreement
        if (isValidSignature(prefixedHash, signature, consumer)) {
            agreements[serviceAgreementId] = Agreement(
                false, new uint8[](0), new uint8[](0), templateId, consumer, new bytes32[](0), new uint256[](0), serviceDefinition, did
            );
            for (uint256 i = 0; i < slaTemplate.conditionKeys.length; i++) {
                if (timeoutValues[i] != 0) {
                    // TODO: define dynamic margin
                    require(
                        timeoutValues[i] > 2,
                        'invalid timeout with a margin (~ 30 to 40 seconds = 2 blocks intervals) to avoid race conditions'
                    );
                    agreements[serviceAgreementId].timeoutValues.push(block.timestamp + timeoutValues[i]);
                } else {
                    agreements[serviceAgreementId].timeoutValues.push(0);
                }
                agreements[serviceAgreementId].conditionsState.push(0);
                agreements[serviceAgreementId].conditionLockedState.push(0);

                // add condition instances
                agreements[serviceAgreementId].conditionInstances.push(keccak256(abi.encodePacked(slaTemplate.conditionKeys[i], valueHash[i])));
                emit ExecuteCondition(
                    serviceAgreementId, keccak256(abi.encodePacked(slaTemplate.conditionKeys[i], valueHash[i])),
                    false, slaTemplate.owner, consumer
                );
            }
            templateId2Agreements[templateId].push(serviceAgreementId);
            emit ExecuteAgreement(serviceAgreementId, templateId, false, slaTemplate.owner, consumer, true);
        } else {
            emit ExecuteAgreement(serviceAgreementId, templateId, false, slaTemplate.owner, consumer, false);
        }
    }

    function splitSignature(bytes signature) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        // Check the signature length
        require(signature.length == 65, 'invalid signature length');
        // inline assembly code for splitting signature into r, v , and s.
        // solium-disable-next-line security/no-inline-assembly
        assembly {
        // first 32 bytes, after the length prefix
            r := mload(add(signature, 32))
        // second 32 bytes
            s := mload(add(signature, 64))
        // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(signature, 96)))
        }
        // check the version
        if (v < 27) {
            v += 27;
        }
        return (v, r, s);
    }

    function fulfillAgreement(bytes32 serviceId) public noPendingFulfillments(serviceId) returns (bool){
        // TODO: handle OR for agreement termination
        agreements[serviceId].state = true;
        emit AgreementFulfilled(serviceId, agreements[serviceId].templateId, templates[agreements[serviceId].templateId].owner);
        return true;
    }

    function fulfillCondition(bytes32 serviceId, bytes4 fingerprint, bytes32 valueHash)
    public isValidControllerHandler(serviceId, fingerprint, valueHash) returns (bool){
        bytes32 conditionKey = keccak256(abi.encodePacked(agreements[serviceId].templateId, msg.sender, fingerprint));
        agreements[serviceId].conditionsState[conditionKeyToIndex[conditionKey]] = 1;
        // Lock dependencies of this condition
        uint dependenciesValue = templates[agreements[serviceId].templateId].dependenciesBits[conditionKeyToIndex[conditionKey]];
        if (dependenciesValue != 0) {
            lockChildConditions(serviceId, conditionKey, dependenciesValue);
        }
        emit ConditionFulfilled(serviceId, agreements[serviceId].templateId, conditionKey);
        return true;
    }

    function revokeAgreementTemplate(bytes32 templateId) public isOwner(templateId) canRevokeTemplate(templateId) returns (bool) {
        templates[templateId].state = false;
        emit SLATemplateRevoked(templateId, true);
    }

    function getTemplateId(bytes32 serviceId) public view returns (bytes32 templateId){
        return agreements[serviceId].templateId;
    }

    function getTemplateStatus(bytes32 templateId) public view returns (bool status){
        return templates[templateId].state;
    }

    function getBitValue(uint256 value, uint16 i, uint16 bitPosition, uint16 numBits) private pure returns (uint8 bitValue) {
        return uint8(value & (2 ** uint256((i * numBits) + bitPosition))) == 0 ? uint8(0) : uint8(1);
    }

    function lockChildConditions(bytes32 serviceId, bytes32 condition, uint256 dependenciesValue) private {
        // check the dependency conditions
        for (uint16 i = 0; i < templates[agreements[serviceId].templateId].conditionKeys.length; i++) {
            if (getBitValue(dependenciesValue, i, 0, 2) != 0) {
                // This is a dependency, lock it
                // verify its state is either 1 or has timed out
                uint8 timeoutFlag = getBitValue(dependenciesValue, i, 1, 2);
                require((agreements[serviceId].conditionsState[i] == 1) || ((timeoutFlag == 1) && conditionTimedOut(serviceId, condition)), 'Invalid state, child dependency expected to be fulfilled or parent timeout occurred.');
                agreements[serviceId].conditionLockedState[i] = 1;
            }
        }
    }

    function hasUnfulfilledDependencies(bytes32 serviceId, bytes32 condition) public view returns (bool status) {
        uint dependenciesValue = templates[agreements[serviceId].templateId].dependenciesBits[conditionKeyToIndex[condition]];
        // check the dependency conditions
        if (dependenciesValue == 0) {
            return false;
        }
        for (uint16 i = 0; i < templates[agreements[serviceId].templateId].conditionKeys.length; i++) {
            if (getBitValue(dependenciesValue, i, 0, 2) != 0) {
                uint8 timeoutFlag = getBitValue(dependenciesValue, i, 1, 2);
                if (timeoutFlag == 1) {
                    if (agreements[serviceId].conditionsState[i] == 1 || !conditionTimedOut(serviceId, condition)) {
                        return true;
                    }
                } else if (agreements[serviceId].conditionsState[i] == 0) {
                    return true;
                }
            }
        }
        return false;
    }

    function conditionTimedOut(bytes32 serviceId, bytes32 condition) public view returns (bool){
        if (block.timestamp > agreements[serviceId].timeoutValues[conditionKeyToIndex[condition]]) return true;
        return false;
    }

    function getCurrentBlockNumber() public view returns (uint){
        return block.number;
    }

    function getConditionStatus(bytes32 serviceId, bytes32 condition) public view returns (uint8){
        return agreements[serviceId].conditionsState[conditionKeyToIndex[condition]];
    }

    function getAgreementStatus(bytes32 serviceId) public view returns (bool){
        return agreements[serviceId].state;
    }

    function getAgreementOwner(bytes32 serviceId) public view returns (address owner) {
        return templates[agreements[serviceId].templateId].owner;
    }

    function getTemplateOwner(bytes32 templateId) public view returns (address owner) {
        return templates[templateId].owner;
    }

    function getTemplateOwnerByServiceId(bytes32 serviceId) public view returns (address owner) {
        return getTemplateOwner(agreements[serviceId].templateId);
    }

    function getServiceAgreementConsumer(bytes32 serviceId) public view returns (address consumer){
        return agreements[serviceId].consumer;
    }

    function getConditionByFingerprint(bytes32 serviceId, address _contract, bytes4 fingerprint) public view returns (bytes32) {
        return keccak256(abi.encodePacked(getTemplateId(serviceId), _contract, fingerprint));
    }

}
