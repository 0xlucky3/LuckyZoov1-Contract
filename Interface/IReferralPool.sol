//SPDX-License-Identifier:MIT
pragma solidity ^0.8.16;

interface IReferralPool {
    function bindReferrer(address _invitee, address _referrer) external;

    function getReferrer(address account) external view returns (address);
}