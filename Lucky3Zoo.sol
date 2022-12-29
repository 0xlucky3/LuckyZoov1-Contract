//SPDX-License-Identifier:MIT

/***

$$\      $$\   $$\  $$$$$$\  $$\   $$\ $$\     $$\ $$$$$$$$\  $$$$$$\   $$$$$$\  
$$ |     $$ |  $$ |$$  __$$\ $$ | $$  |\$$\   $$  |\____$$  |$$  __$$\ $$  __$$\ 
$$ |     $$ |  $$ |$$ /  \__|$$ |$$  /  \$$\ $$  /     $$  / $$ /  $$ |$$ /  $$ |
$$ |     $$ |  $$ |$$ |      $$$$$  /    \$$$$  /     $$  /  $$ |  $$ |$$ |  $$ |
$$ |     $$ |  $$ |$$ |      $$  $$<      \$$  /     $$  /   $$ |  $$ |$$ |  $$ |
$$ |     $$ |  $$ |$$ |  $$\ $$ |\$$\      $$ |     $$  /    $$ |  $$ |$$ |  $$ |
$$$$$$$$\\$$$$$$  |\$$$$$$  |$$ | \$$\     $$ |    $$$$$$$$\  $$$$$$  | $$$$$$  |
\________|\______/  \______/ \__|  \__|    \__|    \________| \______/  \______/ 
                                                                                 
***/

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "./Interface/ILucky3ZooRuleV1.sol";
import "./Interface/IReferralPool.sol";
import "./Shared/ILucky3ZooRuleV1Shared.sol";
import "./Shared/Common.sol";

contract Lucky3Zoo is ILucky3ZooRuleV1Shared,KeeperCompatibleInterface,VRFConsumerBaseV2,Ownable,ReentrancyGuard{

    // INTERFACE OBJECT
    VRFCoordinatorV2Interface ICOORDINATOR;
    ILucky3ZooRuleV1 ILUCKY3ZOORULEV1;
    IReferralPool IREFERRALPOOL;

    //INTERNAL TYPE
    //Configure game fees
    struct GameFee{
        uint singleBetCost;
        uint8 fundFeeRate;
        uint8 winnerFeeRate;
        uint8 level1RewardRate;
        uint8 level2RewardRate;
    }

    //Game result
    struct OpenResult{
        uint8 n1;
        uint8 n2;
        uint8 n3;
    }

    //Game status
    enum GameStatus{
        available,
        pending,
        paused,
        closed
    }

    // CHAINLINK CONFIG (polygon testnet)
    uint32 public vrfCallbackGasLimit=500000;
    uint8 public vrfRequestConfirmations=3;
    uint64 public vrfSubscriptionId=538;
    address private _vrfCoordinator=0xAE975071Be8F8eE67addBC1A82488F1C24858067;
    address private _vrfLinkContract=0xb0897686c545045aFc77CF20eC7A532E3120E0F1;
    bytes32 private _vrfKeyHash=0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd;
    uint private _vrfRequestId;

    // PUBLIC STATE
    address public fundAddress=0xF8b1e47341D4A535bebE2722177E51a86Bf9d052;
    // Game rules contract address
    address public ruleContract;
    // Default referrer
    address public defaultReferrer=0xd8A337eC5a8c9f4837e08Aa776B58C6C1a94D62B;

    address public luckyToken;

    GameStatus public gameStatus;
    GameFee public gameFeeConfig;
    // Total bonuses paid out
    uint public totalBonusPaid;
    // Current round
    uint public currentRound;
    
    // Interval time per round
    uint public roundIntervalTime=3 minutes;
    // Maximum query rounds
    uint public maxQueryRound=500; 
    // Initial fund pool, withdrawable
    // The administrator can only withdraw the initial fund pool, and no one can withdraw other funds in the contract.
    uint public initFundPool=0;

    //Minimum tax threshold
    uint public minTaxThreshold=10 ether;

    // Maximum withdrawable bonus ratio
    uint8 public maxBonusWithdrawalRatio=50;

    //Whether to reward native token
    bool public isRewardToken=false;

    //Reward token multiple
    uint16 public rewardTokenMultiple=10;

    // PRIVATE STATE
    bool private _allowContract=true;
    uint private _lastRequestTime;

    // Mapping from round id to round results
    mapping(uint=>uint8[3]) private _gameResult;
    // Mapping from user address to round list
    mapping(address=>uint[]) private _userBetRound;
    // Mapping from round id to user betting results
    mapping(uint=>mapping(address=>LuckyNumber[])) private _betData;
    // Mapping from round id to user bonus withdrawal status
    mapping(uint=>mapping(address=>bool)) private _bonusWithdrawalStatus;
    mapping(address=>uint) private _userPaidBonus;
    mapping(address=>bool) private _blockAddress; 

    event BetEvt(address indexed user, uint indexed round,uint8[][] numberArray);
    event RoundResultEvt(uint indexed round,uint8[3] result);
    //event WithdrawBonusEvt(address indexed user,uint round,uint amount);
    event WithdrawAllBonusEvt(address indexed user,uint amount);
    event TransferBonusEvt(address indexed from,address indexed to,uint value,int8 level);
    
    constructor(address ruleContractAddress,address referralContractAddress) VRFConsumerBaseV2(_vrfCoordinator){
        ICOORDINATOR=VRFCoordinatorV2Interface(_vrfCoordinator);
        ruleContract=ruleContractAddress;
        ILUCKY3ZOORULEV1=ILucky3ZooRuleV1(ruleContractAddress);
        IREFERRALPOOL=IReferralPool(referralContractAddress);
        _lastRequestTime=block.timestamp;

        // Configure Game Fees
        gameFeeConfig.singleBetCost=2*10**17;
        gameFeeConfig.fundFeeRate=18;
        gameFeeConfig.winnerFeeRate=15;
        gameFeeConfig.level1RewardRate=5;
        gameFeeConfig.level2RewardRate=2;
    }

    modifier gameActive(){
        require(gameStatus==GameStatus.available || gameStatus==GameStatus.paused,"Game unavailable");
        _;
    }

    modifier checkSender(){
        if(!_allowContract){
            require(msg.sender==tx.origin,"Contract access is not allowed");
        }

        require(_blockAddress[msg.sender]==false && _blockAddress[tx.origin]==false,"Access is blocked");
        _;
    }

    //////////////////////////////////
    //Chainlink VRF Start
    function requestRandomWords() internal{
        _vrfRequestId=ICOORDINATOR.requestRandomWords(
            _vrfKeyHash,
            vrfSubscriptionId,
            vrfRequestConfirmations,
            vrfCallbackGasLimit,
            1
        );
    }

    function fulfillRandomWords(uint requestId,uint[] memory randomWords) internal override{
        if(_vrfRequestId==requestId){
            if(gameStatus==GameStatus.pending){
                uint randomNumber=randomWords[0];
                _lastRequestTime=block.timestamp;
                currentRound++;
                uint8[3] memory result=calculate(randomNumber);
                _gameResult[currentRound][0]=result[0];
                _gameResult[currentRound][1]=result[1];
                _gameResult[currentRound][2]=result[2];
                gameStatus=GameStatus.paused;

                emit RoundResultEvt(currentRound,result);
            }
        }
    }

    //Chainlink VRF End
    //////////////////////////////////
    //Chainlink Keepers Start
    //////////////////////////////////

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        if(gameStatus==GameStatus.available &&
          _lastRequestTime+roundIntervalTime <= block.timestamp){
            upkeepNeeded=true;
        }
        else{
            upkeepNeeded=false;
        }
        
        return(upkeepNeeded,'');
    }

    function performUpkeep(bytes calldata) external override{
        if(gameStatus==GameStatus.available && 
        _lastRequestTime+roundIntervalTime <= block.timestamp){
            gameStatus=GameStatus.pending;
            requestRandomWords();
        }
    }

    //Chainlink Keepers End
    //////////////////////////////////

    /**
     * @dev Calculate game result based on random number
     */
    function calculate(uint randomNumber) private view returns(uint8[3] memory){
        uint8[3] memory results;
        uint8 limit=6;
        uint8[6] memory numberMap=[2,4,3,0,5,1];

        if(randomNumber==0){
            randomNumber=uint(keccak256(abi.encodePacked(block.difficulty,block.timestamp,blockhash(block.number-1))));
        }
        
        uint8 t;
        uint8 temp;
        for(uint8 i=0;i<3;i++){
            t=uint8(randomNumber%(limit-i)+i);
            temp=numberMap[i];
            numberMap[i]=numberMap[t];
            numberMap[t]=temp;
            results[i]=numberMap[i];
        }

        return results;
    }

    /**
     * @dev Return user betting data
     */
    function getUserBettedNumber(address user,uint round) public view returns(LuckyNumber[] memory numbers){
        LuckyNumber[] memory luckyNumber=_betData[round][user];
        return luckyNumber;
    }

    /**
     * @dev Get game results
     */
    function getGameResult(uint round) public view returns(uint8[3] memory){
        return _gameResult[round];
    }

    /**
     * @dev Get the top n game results
     */
    function getGameResultList(uint top) public view returns(OpenResult[] memory){
        if(top>currentRound){
            top=currentRound;
        }

        OpenResult[] memory resultList=new OpenResult[](top);

        for(uint i=0;i<top;i++){
            uint8[3] memory result=getGameResult(currentRound-i);
            resultList[i]=OpenResult({n1:result[0],n2:result[1],n3:result[2]});
        }

        return resultList;
    }

    function getLastRoundEndTime() public view returns(uint){
        return _lastRequestTime;
    }

    function getEstimateNextRoundTime() public view returns(uint){
        return _lastRequestTime+roundIntervalTime;
    }
    
    /**
     * @dev Game betting
     *
     * - `numberArray` [[2,3,4,1,0],[1,2,3,1,1]]
     * - `referrer` referrer address or zero address
     */
    function batchBetting(uint8[][] calldata numberArray,address referrer) payable public gameActive checkSender{
        require(numberArray.length>0,"Incorrect format");
        uint multiple=0;

        for(uint8 i=0;i<numberArray.length;i++){
            require(ILUCKY3ZOORULEV1.verifyFormat(numberArray[i])==true,"Incorrect format");
            LuckyNumber memory betNumber=ILUCKY3ZOORULEV1.formatObject(numberArray[i]);
            
            multiple+=betNumber.x;
        }

        uint totalFee=multiple*gameFeeConfig.singleBetCost;
        require(msg.value>=totalFee,"Insufficient fee");

        address sender=msg.sender;

        if(_betData[currentRound+1][sender].length==0){
            _userBetRound[sender].push(currentRound+1);
        }

        if((referrer==address(0) || referrer==sender) && defaultReferrer!=address(0)){
            referrer=defaultReferrer;
        }

        address level1Ref=IREFERRALPOOL.getReferrer(sender);
        address level2Ref=address(0);

        if(level1Ref==address(0) && referrer!=address(0)){
            IREFERRALPOOL.bindReferrer(sender,referrer);
            level1Ref=referrer;
        }

        for(uint8 i=0;i<numberArray.length;i++){
            LuckyNumber memory betNumber=ILUCKY3ZOORULEV1.formatObject(numberArray[i]);
            _betData[currentRound+1][sender].push(betNumber);
        }

        if(level1Ref!=address(0) && level1Ref!=sender){
            if(gameFeeConfig.level1RewardRate>0){
                uint bonus=totalFee*gameFeeConfig.level1RewardRate/100;
                payable(level1Ref).transfer(bonus);
                emit TransferBonusEvt(sender,level1Ref,bonus,1);
            }

            level2Ref=IREFERRALPOOL.getReferrer(level1Ref);

            if(gameFeeConfig.level2RewardRate>0){
                uint bonus=totalFee*gameFeeConfig.level2RewardRate/100;
                if(level2Ref!=address(0) &&  level2Ref!=sender){
                    payable(level2Ref).transfer(bonus);
                    emit TransferBonusEvt(sender,level2Ref,bonus,2);
                }
                else if(defaultReferrer!=address(0)){
                    payable(defaultReferrer).transfer(bonus);
                }
            }
        }

        if(fundAddress!=address(0) && gameFeeConfig.fundFeeRate>0){
            payable(fundAddress).transfer(totalFee*gameFeeConfig.fundFeeRate/100);
        }

        if(gameStatus==GameStatus.paused){
            gameStatus=GameStatus.available;
            _lastRequestTime=block.timestamp;
        }

        //reward token
        uint rewardTokenQty=totalFee*rewardTokenMultiple;
        if(isRewardToken && luckyToken!=address(0) && IERC20(luckyToken).balanceOf(address(this))>=rewardTokenQty){
            TransferHelper.safeTransfer(luckyToken,sender,rewardTokenQty);
        }

        emit BetEvt(sender,currentRound+1,numberArray);
    }

    /**
     * @dev Get the bonuses that the user has already withdrawn
     */
    function getPaidBonus(address user) public view returns(uint){
        return _userPaidBonus[user];
    }

    /**
     * @dev Returns the list of rounds the user has bet on.
     */
    function queryUserBettedRound(address user,uint cursor,uint size) public view returns(uint[] memory list,bool[] memory result){
        uint[] memory roundList=_userBetRound[user];
        
        if(roundList.length==0){
            return (list,result);
        }

        uint querySize=size;
        if(querySize>(roundList.length-cursor)){
            querySize=roundList.length-cursor;
        }

        list=new uint[](querySize);
        result=new bool[](querySize);
        uint j=0;
        uint k=roundList.length-cursor;
        for(uint i=k;i>k-querySize;i--){
            list[j]=roundList[i-1];
            result[j]=verifyRoundResult_(user,list[j]);
            j++;
        }

        return (list,result);
    }

    function getUserRoundStatus(address user,uint round) public view returns(uint8 status,uint bonus){
        LuckyNumber[] memory luckyNumber=_betData[round][user];
        if(luckyNumber.length==0) return (0,0);

        bonus=queryBonus(user,round);

        status=bonus>0?2:1;
    }

    function verifyRoundResult_(address user,uint round) private view returns(bool){
        if(round==currentRound+1){
            return false;
        }

        LuckyNumber[] memory userBetData=_betData[round][user];
        uint8[3] memory result=_gameResult[round];
        
        for(uint i=0;i<userBetData.length;i++){
            if(ILUCKY3ZOORULEV1.verifyResult(userBetData[i],result)){
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Query for all undrawn bonuses
     */
    function queryAllUnPaidBonus(address user) public view returns(uint){
        uint[] memory roundList=_userBetRound[user];
        if(roundList.length==0) return 0;

        uint querySize=roundList.length;
        if(querySize>maxQueryRound){
            querySize=maxQueryRound;
        }

        uint bonus=0;

        for(uint i=roundList.length;i>roundList.length-querySize;i--){
            bonus+=queryUnPaidBonus(user,roundList[i-1]);
            
        }

        return bonus;
    }

    /**
     * @dev Query bonus
     */
    function queryBonus(address user,uint round) public view returns(uint){
        if(round==currentRound+1 || _gameResult[round].length==0){
            return 0;
        }
        
        uint8[3] memory roundResult=_gameResult[round];
        LuckyNumber[] memory userBetData=_betData[round][user];

        uint bonus=0;      
        for(uint i=0;i<userBetData.length;i++){

            if(ILUCKY3ZOORULEV1.verifyResult(userBetData[i],roundResult)){
                uint16 multiple=ILUCKY3ZOORULEV1.getModeMultiple(userBetData[i].mode);
                bonus+= gameFeeConfig.singleBetCost*multiple/10;
            }
            
        }

        return bonus;
    }
    

    function getBalance() public view returns(uint){
        return address(this).balance;
    }
    
    /**
     * @dev Query for undrawn bonuses
     */
    function queryUnPaidBonus(address user,uint round) public view returns(uint){
        if(_bonusWithdrawalStatus[round][user]==true){
            return 0;
        }

        return queryBonus(user,round);
    }

    /**
     * @dev Withdraw all bonuses
     */
    function withdrawAllBonus() public nonReentrant checkSender{
        address winner=msg.sender;
        uint balance=getBalance();
        uint[] memory roundList=_userBetRound[winner];
        require(roundList.length>0,"Your bonus is not enough");

        uint querySize=roundList.length;
        if(querySize>maxQueryRound){
            querySize=maxQueryRound;
        }

        uint bonus=0;

        for(uint i=roundList.length;i>roundList.length-querySize;i--){
            bonus+=queryUnPaidBonus(winner,roundList[i-1]);
            _bonusWithdrawalStatus[roundList[i-1]][winner]=true;
        }

        require(bonus>0,"Your bonus is not enough");
        require(balance>=bonus,"Insufficient bonuses available");
        totalBonusPaid+=bonus;

        if(maxBonusWithdrawalRatio>0){
            uint maxBonus=(balance*maxBonusWithdrawalRatio)/100;
            bonus=bonus<maxBonus?bonus:maxBonus;
        }

        //Check if you need to pay taxes
        if(bonus>=minTaxThreshold && gameFeeConfig.winnerFeeRate>0 && fundAddress!=address(0)){
            uint fee=(bonus*gameFeeConfig.winnerFeeRate)/100;
            payable(fundAddress).transfer(fee);
            
            if(bonus-fee >0){
                payable(winner).transfer(bonus-fee);
            }
        }
        else{
            payable(winner).transfer(bonus);
        }

        emit WithdrawAllBonusEvt(winner,bonus);
    }

    /**========================================================================================================**/
    /**The basic settings of the contract, when the game runs stably, the management authority will be destroyed**/
    /**========================================================================================================**/

    /**
     * @dev Deposit initial funds
     */
    function depositInitFundPool() payable public{
        require(msg.value>0,"Deposit amount is 0");
        initFundPool+=msg.value;
    }

    /**
     * @dev Withdraw initial funds
     */
    function withdrawalInitFundPool(address to,uint amount) public onlyOwner{
        require(initFundPool>0,"InitFundPool balance is 0");
        require(amount<=initFundPool,"Withdrawal amount exceeds limit");
        initFundPool-=amount;
        payable(to).transfer(amount);
    }

    /**
     * @dev Controls the game state, usually closing the game when threatened
     */
    function setGameStatus(GameStatus status) external onlyOwner{
        gameStatus=status;
    }

    /**
     * @dev VRF Settings
     */
    function setVrfGasLimitAndConfirmations(uint32 gasLimit,uint8 confirmations,uint64 subscriptionId) external onlyOwner{
        vrfCallbackGasLimit=gasLimit;
        vrfRequestConfirmations=confirmations;
        vrfSubscriptionId=subscriptionId;
    }

    /**
     * @dev Adjust rates based on community consensus
     */
    function setFee(GameFee calldata feeConfig) external onlyOwner{
        gameFeeConfig=feeConfig;
    }

    /**
     * @dev Set the interval between each round
     */
    function setIntervalTime(uint time) external onlyOwner{
        roundIntervalTime=time;
    }

    /**
     * @dev Set the maximum number of rounds for query, exceeding this value will not be queried
     */
    function setQueryMaxRound(uint maxRound) external onlyOwner{
        maxQueryRound=maxRound;
    }

    /**
     * @dev Set the maximum bonus ratio for a single withdrawal
     */
    function setMaxBounsRate(uint8 rate) external onlyOwner{
        maxBonusWithdrawalRatio=rate;
    }

    /**
     * @dev Control contract access
     */
    function setAllowContract(bool isAllow) external onlyOwner{
        _allowContract=isAllow;
    }

    /**
     * @dev Set fund address
     */
    function setFundAddress(address addr) external onlyOwner{
        fundAddress=addr;
    }

    /**
     * @dev Set default referrer address
     */
    function setDefaultReferrerAddress(address addr) external onlyOwner{
        defaultReferrer=addr;
    }

    /**
     * @dev Configure reward native token
     */
    function setLuckyTokenConfig(address token,bool isReward,uint16 rewardMultiple) external onlyOwner{
        luckyToken=token;
        isRewardToken=isReward;
        rewardTokenMultiple=rewardMultiple;
    }

    /**
     * @dev Block malicious users
     */
    function addBlockUser(address user) external onlyOwner{
        require(_blockAddress[user]==false,"");
        _blockAddress[user]=true;
    }

    /**
     * @dev Unblock
     */
    function removeBlockUser(address user) external onlyOwner{
        require(_blockAddress[user]==true,"");
        delete _blockAddress[user];
    }

    receive() external payable {}
}
