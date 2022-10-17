// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./MineLogic.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract MineFactory is Ownable{

    event newLogic(bool changed);
    event contractCreation(address clone, address deployer);

    address public logicContract;

    using Clones for address;
   
   

    constructor() public {
        logicContract = address (new MineLogic());
    }

    function createContract(bytes32 salt, uint material, uint _batchLimit, uint _totalTime, uint _enterTime, uint _timeLimit, address _manager) public {
        address clone = Clones.cloneDeterministic(logicContract, salt);

        MineLogic(clone).initialize(material, _batchLimit, _totalTime, _enterTime, _timeLimit, _manager);
    
        emit contractCreation(clone, msg.sender);
    }

    function changeContract(address _logic) external onlyOwner {
        logicContract = _logic;
        emit newLogic(bool(true));
    }

}