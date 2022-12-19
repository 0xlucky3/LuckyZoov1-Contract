//SPDX-License-Identifier:MIT
pragma solidity ^0.8.6;

interface ILucky3ZooRuleV1Shared {
    struct LuckyNumber{
        uint8 n1;
        uint8 n2;
        uint8 n3;
        uint8 x;
        GameMode mode;
    }

    enum GameMode{
        Strict,
        Any,
        AnyTwo,
        AnyOne
    }

}