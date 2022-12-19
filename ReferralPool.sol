//SPDX-License-Identifier:MIT
pragma solidity ^0.8.16;


import "@openzeppelin/contracts/access/Ownable.sol";

contract ReferralPool is Ownable {

    mapping(address => address) private referrer; // My recommended address (superior)
    mapping(address => address[]) private invitees; // User's inviter array mapping (subordinate list)
    mapping(address=>bool) private allowCaller;
   
    event BindReferrer(address indexed invitee, address indexed referrer);
    event ReferrerDividend(address indexed referrer, uint256 indexed amount);

    constructor() {
        
    }
  
    modifier onlyTokenCall() {
        require(allowCaller[_msgSender()] == true, 'Only be called by token');
        _;
    }

    function getMin(uint256 a, uint256 b) private pure returns (uint256) {
        return a >= b ? b : a;
    }

    // Binding referrer relationship (binding superior)
    function bindReferrer(address _invitee, address _referrer) external onlyTokenCall {
        if (referrer[_invitee] == address(0) && _invitee != _referrer && referrer[_referrer]!=_invitee) {
            referrer[_invitee] = _referrer;
            invitees[_referrer].push(_invitee);
            emit BindReferrer(_invitee, _referrer);
        }
    }
    // Get the referrer address of the account
    function getReferrer(address account) public view returns (address) {
        return referrer[account];
    }

    // Get the direct push address of the account
    function getInvitee(address account, uint256 index) public view returns (address) {
        return invitees[account][index];
    }

    // Get the number of direct pushes for an account
    function getTInviteeCount(address account) public view returns (uint256) {
        return invitees[account].length;
    }

    function addAllowCaller(address user) public onlyOwner{
        allowCaller[user]=true;
    }

    function removeAllowCaller(address user) public onlyOwner{
        allowCaller[user]=false;
    }

}