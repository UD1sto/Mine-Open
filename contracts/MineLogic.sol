pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MineLogic is Initializable, OwnableUpgradeable {

    enum states { //game states
        preStart,
        inProgress,
        finished
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Not manager");
        _;
    }

    modifier onlyMiner() {
        require(miners[msg.sender].validated == true, "Not miner");
        _;
    }

    modifier onlyTreater() {
        require(treaters[msg.sender].validated == true, "Not treater");
        _;
    }

    modifier onlyEvaluator() {
        require(evaluators[msg.sender].validated == true, "Not evaluator");
        _;
    }

    modifier inProgress() {
        require(state == states.inProgress, "Not in progress");
        _;
    }

    states public state;
   
    //kgs that a batch can hold
    uint public batchLimit;
    //current number of batches
    uint public batchNo;
    //time last
    uint enterTime;
    uint timeLimit;
    uint totalTime;
    //inclusion merkle roots
    bytes32 public minersRoot;
    bytes32 public evaluatorsRoot;
    bytes32 public treatersRoot;
    //manager address
    address public manager;
    //batches initialized from manager
    bytes32 [] public production;
    //counts the 
    uint public productCounter;
    //tracking url batch id
    bytes32 public trackingUrl;
    //documents verifying export and transport to airport
    bytes32 public exportDocs;


 

    struct member {
        bool validated;
        bool status;  
    }

    struct product {
        bool forSale;
        bool sold;
        uint price;
        address miner;
        bytes32 tracking;
    }
    
    // used to count the stones mined that are not yet included in a batch
    address [] public minersList;
    bytes32 [] public stoneList;
    uint [] public weightList;
    
    //struct that contains batch information
    struct batch {
        bool exists;
        uint no;
        bytes32[] hashes;
        uint timeOfStart;
        uint status;
        uint miner;
        address evaluator;
        address treater;
        bytes32 [] stones;
        address [] cultivators;
        uint [] weights;
        bytes32 [] successionHashes;
    }
    //role mappings
    mapping(address => member) public miners;
    mapping(address => member) public evaluators;
    mapping(address => member) public treaters;
    
    //batch & product mappings
    mapping (bytes32 => batch) public batches;
    mapping (bytes32 => product) public products;
    


    function Initialialize(
        uint material, uint _batchLimit, uint _totalTime, uint _enterTime, uint _timeLimit, address _manager) 
           public initializer {
        require (material > 0, "Material must be greater than 0");

        batchLimit = _batchLimit;
        totalTime = _totalTime;
        enterTime = _enterTime;
        timeLimit = _timeLimit;
        manager = _manager;
        state = states.preStart;
    }

    function merkleProove(bytes32[] calldata _merkleProof, uint role) public {
        require (block.timestamp < enterTime, "Time to enter has passed");
        require (state == states.preStart, "Game is not in progress");
        require(miners[msg.sender].validated == true ||
        evaluators[msg.sender].validated == true ||
        treaters[msg.sender].validated == true
        );
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        
        if (role == 1) {

            require(
            MerkleProof.verify(_merkleProof, minersRoot, leaf),
            "Invalid Merkle Proof."
        );
           
            miners[msg.sender].validated = true;
            
        } else if (role == 2) {

            require(
            MerkleProof.verify(_merkleProof, evaluatorsRoot, leaf),
            "Invalid Merkle Proof."
        );

            evaluators[msg.sender].validated = true;
           
        } else if (role == 3) {

            require(
            MerkleProof.verify(_merkleProof, treatersRoot, leaf),
            "Invalid Merkle Proof."
        );
           
            treaters[msg.sender].validated = true;

        } else {
            revert("Invalid role");
        }
        
    
    }


    function inputStone(bytes32 [] calldata photos, uint [] calldata weight) external onlyMiner inProgress {
        require (weight.length == photos.length , "Photos and weights must be the same length");
        require (weight.length > 0, "Photos and weights must be greater than 0");

        for (uint i = 0; i < photos.length; i++) {
            stoneList.push(photos[i]);
            weightList.push(weight[i]);
            minersList.push(msg.sender);
        }
    }
    
    //select evaluator(s) and treater(s), index and time of return
    function initiateBatch(bytes32 batchHash, address _evaluator, address _treater) external onlyManager inProgress{
        require (productCounter <= batchLimit, "Batch limit reached");

        production.push(batchHash);
        productCounter = 0;
        batchNo += 1;
        batches[batchHash].no = batchNo;
        batches[batchHash].exists = true;
        batches[batchHash].evaluator = _evaluator;
        batches[batchHash].treater = _treater;
        batches[batchHash].stones = stoneList;
        batches[batchHash].weights = weightList;
        batches[batchHash].cultivators = minersList;           
    }
    //dev: are evaluated from IOT device
    function evaluateBatch(bytes32 idHash, bytes32 newHash, bytes32 [] calldata photosEv, address [] calldata cultEv, uint [] calldata weightEv) external onlyEvaluator inProgress{
        require (batches[idHash].exists == true, "Batch does not exist");
        require (batches[idHash].evaluator == msg.sender, "Not evaluator");
        require (batches[idHash].status == 0, "Batch already evaluated");
        require (photosEv.length <= batches[idHash].stones.length &&
        cultEv.length == photosEv.length &&
        weightEv.length == photosEv.length, "Lesser or equal to previous arrays");



        batches[idHash].status = 1;
        batches[idHash].stones = photosEv;
        batches[idHash].cultivators = cultEv;
        batches[idHash].weights = weightEv;
        batches[idHash].hashes.push(newHash);
    }
    //dev: after evaluation and before treatment depending on the evaluation output, rule breakers will be removed from their roles
    function measures(address [] calldata cultDel) external onlyManager inProgress{ //can only be triggered once
        require(cultDel.length > 0, "At least one address must be provided");

        for (uint i =  0; i < cultDel.length; i++) {
            if (miners[cultDel[i]].validated == true) {
                miners[cultDel[i]].status = false;     
        }
        }

    }
// after measures the batch is transported to treater-cutter, the manager is responsible for managing the transportation of the goods off chain and then
//the hash of the url tracking link on chain
    function transportBatch(bytes32 idHash, bytes32 _trackingUrl) external onlyManager{
        require (batches[idHash].status == 1, "Batch already transported");
        require(trackingUrl == 0x0, "Tracking url already set");
        trackingUrl = _trackingUrl;
        batches[idHash].status = 2;
    }

    function comfirmDelivered(bytes32 idHash) external onlyTreater inProgress{
        require (batches[idHash].status == 2, "Batch already confirmed");

        batches[idHash].status = 3;
    }

    function treatBatch(bytes32 idHash, bytes32 newHash, bytes32 [] calldata photosTr, address [] calldata cultTr, uint [] calldata weightTr) external onlyTreater{
        require (batches[idHash].status == 3, "Batch already treated");
        batches[idHash].status = 4;

        

    }

    function exportBatch(bytes32 idHash, bytes32 _exportDocs) external onlyManager inProgress{
        require (batches[idHash].status == 4, "Batch already treated");

        batches[idHash].status = 5;
        exportDocs = _exportDocs;
    }

    function initializeSelling(bytes32 idHash, uint [] calldata prices) external onlyManager{
        require (batches[idHash].status == 5, "already init");

        for( uint i = 0; i < batches[idHash].stones.length; i++) {
            products[batches[idHash].stones[i]].forSale = true;
            products[batches[idHash].stones[i]].price = prices[i];
            products[batches[idHash].stones[i]].miner = batches[idHash].cultivators[i];  
        }

        batches[idHash].status = 6;
    }

    function buyStone(bytes32 item) external payable {
        require (products[item].forSale == true, "Stone not for sale");
        require (products[item].price <= msg.value, "Price not correct");
        require (products[item].sold == true, "Stone not sold");
     
        products[item].sold = true;
        payable(products[item].miner).transfer(msg.value / 10 * 7);
    }

    function inputTracking(bytes32 idHash, bytes32 [] calldata urls) external onlyManager {
        require (urls.length > 0, "At least one url must be provided");
        
        for (uint i = 0; i < urls.length; i++) {
           require (products[batches[idHash].stones[i]].sold == true, "Stone not sold");
           products[batches[idHash].stones[i]].tracking = urls[i];
          
        }
    }

    function withdraw(uint amount) external onlyOwner {
        require (address(this).balance >= amount, "Not enough funds");
        payable(msg.sender).transfer(amount);
    }




}