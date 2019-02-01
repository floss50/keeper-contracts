pragma solidity 0.5.3;

import '../../SEA/PaymentConditions.sol';
import '../../SEA/ServiceExecutionAgreement.sol';
import 'zos-lib/contracts/Initializable.sol';


contract PaymentConditionsChangeInStorage is PaymentConditions {
    // keep track of how many times a function was called.
    mapping (address=>uint256) public called;
}
