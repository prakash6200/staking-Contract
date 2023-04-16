// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./ITRC20.sol";
import "./Ownable.sol";

contract Stake is Ownable {

    ITRC20 private token; 

    uint256 private lockPeriod = 5 minutes;

    bool private emergencyWithdrawalStatus = false;

    bool private initialized = false;

    uint256 private stakingId = 0;

    struct Pool {
        address tokenAddress;
        uint256 rewardToken1Per;  // SM token
        uint256 rewardToken2Per;  // Other Reward token 
        address rewardAddress;
        bool pause;
        uint256 rewardAPY;
        uint256 time;
    }

    struct StakeStruct {
        address staker;
        uint256 amount;
        uint256 stakeTime;
        uint256 unstakeTime;
        uint256 harvested;
        uint256 poolId;
    }

    struct UserStruct{
        uint256[] stakingIds;
        uint256 totalStakeAmount;
        uint256 totalHarvestAmount;
    }
    
    Pool[] public pool;
    
    mapping (address => UserStruct) public userDetails;
    mapping (uint256 => StakeStruct) public stakeDetails;

    event UnStaked(address _staker, uint256 _stakeId, uint256 _poolId, uint256 _amount, uint256 _time);
    event Harvested(address _staker, uint256 _stakeId,uint256 _poolId, uint256 _amount, uint256 _time);
    event PoolCreated(address _poolAddress, uint256 _rewardToken1Per, uint256 _rewardToken2Per, address _rewardAddress, uint256 _rewardAPY, uint256 _time);
    event Staked(address _staker, uint256 _stakeId, uint256 _poolId, uint256 _amount, uint256 _time);
    event UnstakeRequest(address _staker, uint256 _stakeId,uint256 _poolId, uint256 _amount, uint256 _time);

    function initializeToken(address _token) onlyOwner public returns (bool) {
        require(!initialized, "Already Initialized");
        initialized = true;
        token = ITRC20(_token);
        return true;
    }

    function emergencyWithdrawal() onlyOwner public returns(bool){
        emergencyWithdrawalStatus = !emergencyWithdrawalStatus;
        return true;
    }

    function changeLockPeriod(uint256 _time)public onlyOwner returns (bool){
        lockPeriod = _time;
        return true;
    }

    function changeRewardTokenAPYPer(uint256 _reward1TokenPer, uint256 _reward2TokenPer, uint256 _rewardAPY, uint256 _poolId) public onlyOwner returns (bool){
        pool[_poolId].rewardToken1Per = _reward1TokenPer;
        pool[_poolId].rewardToken2Per = _reward2TokenPer;
        pool[_poolId].rewardAPY = _rewardAPY;
        return true;
    }

    function isPoolPause(uint poolId) onlyOwner public returns(bool){
        pool[poolId].pause =!pool[poolId].pause;
        return true;
    }

    function createPool(address _tokenAddress, uint256 _rewardToken1Per, uint256 _rewardToken2Per, address _rewardAddress, uint256 _rewardAPY) onlyOwner public returns(bool) {
        require(_tokenAddress != address(0), "Zero Address");
        Pool memory poolInfo;
        poolInfo = Pool({
            tokenAddress : _tokenAddress,
            rewardToken1Per : _rewardToken1Per,
            rewardToken2Per : _rewardToken2Per,
            rewardAddress: _rewardAddress,
            rewardAPY : _rewardAPY,
            pause : false,
            time : block.timestamp
        });
        pool.push(poolInfo);
        emit PoolCreated(_tokenAddress, _rewardToken1Per, _rewardToken2Per, _rewardAddress, _rewardAPY, block.timestamp);
        return true;
    }

    function poolLength() public view returns(uint256){
        return pool.length;
    }

    function staking(uint256 _amount, uint256 _poolId) public  returns(bool) {
        require(pool[_poolId].pause != true, "Pool Paused");
        require(pool[_poolId].tokenAddress != address(0), "Pool not exist");
        require (ITRC20(pool[_poolId].tokenAddress).allowance(msg.sender, address(this)) >= _amount, "Token not approved");
        ITRC20(pool[_poolId].tokenAddress).transferFrom(msg.sender, address(this), _amount);
        StakeStruct memory stakerinfo;
        stakerinfo = StakeStruct({
            staker:msg.sender,
            amount: _amount,
            stakeTime : block.timestamp,
            unstakeTime : 0,
            harvested: 0,
            poolId : _poolId
        });
        stakeDetails[stakingId] = stakerinfo;
        userDetails[msg.sender].totalStakeAmount += _amount;
        userDetails[msg.sender].totalHarvestAmount += 0;
        userDetails[msg.sender].stakingIds.push(stakingId);
        emit Staked(msg.sender, stakingId, _poolId, _amount, block.timestamp);
        stakingId++;     
        return true;
    } 

    function _unstakingRequest(uint256 _stakingId) private returns(bool){
        require(pool[stakeDetails[_stakingId].poolId].pause != true, "Pool Paused");
        require(stakeDetails[_stakingId].stakeTime != 0, "Token not exist");
        stakeDetails[_stakingId].unstakeTime = block.timestamp + lockPeriod;
        emit UnstakeRequest(msg.sender, _stakingId, stakeDetails[_stakingId].poolId, stakeDetails[_stakingId].amount, stakeDetails[_stakingId].unstakeTime);
        return true;
    }

    function unstakingRequest() public returns(bool){
        for(uint i=0; i<userDetails[msg.sender].stakingIds.length; i++){
            if(stakeDetails[userDetails[msg.sender].stakingIds[i]].unstakeTime == 0){
                _unstakingRequest(userDetails[msg.sender].stakingIds[i]);
            }      
        }
        return true;
    }

    function _unstaking(uint256 _stakingId) private returns (bool){
        require(pool[stakeDetails[_stakingId].poolId].pause != true, "Pool Paused");
        require(stakeDetails[_stakingId].stakeTime != 0, "Token not exist");
        if(emergencyWithdrawalStatus == false){
            require(stakeDetails[_stakingId].unstakeTime != 0, "First request for unstake");
            require(stakeDetails[_stakingId].unstakeTime <= block.timestamp, "Token can unstake after locking period");
        }
        if(getCurrentReward( _stakingId) > 0){
            _harvest(msg.sender, _stakingId);
        }
        if(stakeDetails[_stakingId].amount>0){
            ITRC20(pool[stakeDetails[_stakingId].poolId].tokenAddress).transfer(msg.sender, stakeDetails[_stakingId].amount);
            userDetails[msg.sender].totalStakeAmount -= stakeDetails[_stakingId].amount;
            stakeDetails[_stakingId].amount = 0;
            stakeDetails[_stakingId].unstakeTime = block.timestamp;
        }
        
        // for(uint256 i=0; i<userDetails[msg.sender].stakingIds.length; i++){
        //     if(userDetails[msg.sender].stakingIds[i] == _stakingId){
        //         userDetails[msg.sender].stakingIds[i] = userDetails[msg.sender].stakingIds[userDetails[msg.sender].stakingIds.length-1];
        //         delete userDetails[msg.sender].stakingIds[userDetails[msg.sender].stakingIds.length-1];
        //         userDetails[msg.sender].stakingIds.pop();
        //         break;
        //     }
        // }
        // delete stakeDetails[_stakingId];

        emit UnStaked(msg.sender, _stakingId, stakeDetails[_stakingId].poolId, stakeDetails[_stakingId].amount, block.timestamp);
        return true;  
    }

    function unstaking() public  returns (bool) {
        for(uint i=0; i<userDetails[msg.sender].stakingIds.length; i++){
            _unstaking(userDetails[msg.sender].stakingIds[i]);
        }
        return true;
    }

    // function harvest(uint256 _stakingId) private  returns (bool) {
    //     _harvest(msg.sender, _stakingId);
    //     return true;
    // }

    function harvest() public  returns (bool) {
        for(uint i=0; i<userDetails[msg.sender].stakingIds.length; i++){
            _harvest(msg.sender, userDetails[msg.sender].stakingIds[i]);
        }
        return true;
    }

    function _harvest(address _user, uint256 _stakingId) internal  {
        require(getCurrentReward(_stakingId) > 0, "Nothing to harvest");
        require(pool[stakeDetails[_stakingId].poolId].pause != true, "Pool Paused");
        uint256 harvestAmount = getCurrentReward(_stakingId);
        stakeDetails[_stakingId].harvested += harvestAmount;
        ITRC20(pool[stakeDetails[_stakingId].poolId].rewardAddress).transfer(_user, (harvestAmount*pool[stakeDetails[_stakingId].poolId].rewardToken2Per)/100);

        token.transfer(_user, (harvestAmount*pool[stakeDetails[_stakingId].poolId].rewardToken1Per)/100);

        userDetails[msg.sender].totalHarvestAmount += harvestAmount;
        emit Harvested(_user, _stakingId, stakeDetails[_stakingId].poolId, harvestAmount, block.timestamp);
    }

    function getTotalReward( uint256 _stakingId) public view returns (uint256) {  
        if(stakeDetails[_stakingId].unstakeTime != 0){
            if(block.timestamp < stakeDetails[_stakingId].unstakeTime){      
                return (((block.timestamp - stakeDetails[_stakingId].stakeTime)) * stakeDetails[_stakingId].amount *  pool[stakeDetails[_stakingId].poolId].rewardAPY / 100) / 1 days;
            } else {
                return (((stakeDetails[_stakingId].unstakeTime - stakeDetails[_stakingId].stakeTime)) * stakeDetails[_stakingId].amount *  pool[stakeDetails[_stakingId].poolId].rewardAPY / 100) / 1 days;
            }
        } else {
          return  (((block.timestamp - stakeDetails[_stakingId].stakeTime)) * stakeDetails[_stakingId].amount *  pool[stakeDetails[_stakingId].poolId].rewardAPY / 100) / 1 days;
        }
    }

    function getCurrentReward( uint256 _stakingId) public view returns (uint256) {
        if(stakeDetails[_stakingId].amount != 0){
            return (getTotalReward( _stakingId)) - (stakeDetails[_stakingId].harvested);
        } else {
            return 0;
        }
    }

    function getToken() public view returns (ITRC20) {
        return token;
    }

    function getStakeLength(address _account) public view returns(uint256) {
        return userDetails[_account].stakingIds.length;
    }

    function transferTokens(uint256 _amount) public onlyOwner{
        require(token.balanceOf(address(this)) > _amount , "Not Enough Tokens");
        token.transfer(owner(), _amount);
    }

    function viewEmergencyWithdrawalStatus() public view returns(bool){
        return emergencyWithdrawalStatus;
    }
}