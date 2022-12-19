//SPDX-License-Identifier:MIT
pragma solidity ^0.8.16;

import "../Shared/ILucky3ZooRuleV1Shared.sol";

interface ILucky3ZooRuleV1 is ILucky3ZooRuleV1Shared {
    
    function getBlankCode() external pure returns(uint);

    function verifyResult(LuckyNumber memory a,uint8[3] memory b) external pure returns(bool);

    function verifyFormat(uint8[] memory numberArr) external view returns(bool);

    function formatObject(uint8[] memory numberArr) external pure returns(LuckyNumber memory);

    function getModeMultiple(GameMode mode) external view returns(uint16);
}