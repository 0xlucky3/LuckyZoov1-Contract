//SPDX-License-Identifier:MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interface/ILucky3ZooRuleV1.sol";

contract Lucky3ZooRuleV1 is ILucky3ZooRuleV1,Ownable{
    //CONSTANTS
    uint8 private constant BLANKCODE=10;
    uint8 private constant MAXNUMBER=5;

    uint public MaxMultiple=1000;

    mapping(GameMode=>uint16) private _bonusMultiple; //x10

    constructor(){
        _bonusMultiple[GameMode.Strict]=800;
        _bonusMultiple[GameMode.Any]=120;
        _bonusMultiple[GameMode.AnyTwo]=180;
        _bonusMultiple[GameMode.AnyOne]=30;
    }

    function getBlankCode() override public pure returns(uint){
        return BLANKCODE;
    }

    function getModeMultiple(GameMode mode) override public view returns(uint16){
        return _bonusMultiple[mode];
    }

    function formatObject(uint8[] memory numberArr) override public pure returns(LuckyNumber memory){
        return LuckyNumber({n1:numberArr[0],n2:numberArr[1],n3:numberArr[2],x:numberArr[3]==0?1:numberArr[3],mode:GameMode(numberArr[4])});
    }

    function verifyFormat(uint8[] memory numberArr) override public view returns(bool){
        if(numberArr.length!=5){
            return false;
        }

        //verify single bet multiple 
        if(numberArr[3]>MaxMultiple){
            return false;
        }

        for(uint8 i=0;i<3;i++){
            if(numberArr[i]!=BLANKCODE && numberArr[i]>MAXNUMBER){
                return false;
            }
        }

        return true;
    }

    function verifyResult(LuckyNumber memory a,uint8[3] memory b) override public pure returns(bool){
        if(a.mode==GameMode.Strict){
            if(a.n1==b[0] && a.n2==b[1] && a.n3==b[2]){
                return true;
            }
        }
        else if(a.mode==GameMode.Any){
            if(a.n1+a.n2+a.n3 != b[0]+b[1]+b[2]){
                return false;
            }
            for(uint8 i=0;i<3;i++){
                if(a.n1!=b[i] && a.n2!=b[i]&& a.n3!=b[i]){
                    return false;
                }
                if(i==0){
                    if(a.n1!=b[0] && a.n1!=b[1] && a.n1!=b[2]){
                        return false;
                    }
                }
                if(i==1){
                    if(a.n2!=b[0] && a.n2!=b[1] && a.n2!=b[2]){
                        return false;
                    }
                }
                if(i==2){
                    if(a.n3!=b[0] && a.n3!=b[1] && a.n3!=b[2]){
                        return false;
                    }
                }
            }
            return true;
        }
        else if(a.mode==GameMode.AnyTwo){ //any two
            if(a.n1==BLANKCODE && a.n2==b[1] && a.n3==b[2]){
                return true;
            }
            if(a.n2==BLANKCODE && a.n1==b[0] && a.n3==b[2]){
                return true;
            }
            if(a.n3==BLANKCODE && a.n1==b[0] && a.n2==b[1]){
                return true;
            }
        }
        else if(a.mode==GameMode.AnyOne){  //any one
            if(a.n1!=BLANKCODE && a.n2==BLANKCODE && a.n3==BLANKCODE && a.n1==b[0]){
                return true;
            }
            if(a.n2!=BLANKCODE && a.n1==BLANKCODE && a.n3==BLANKCODE && a.n2==b[1]){
                return true;
            }
            if(a.n3!=BLANKCODE && a.n1==BLANKCODE && a.n2==BLANKCODE && a.n3==b[2]){
                return true;
            }
        }
        
        return false;
    }

    function updateBonusMultiple(GameMode mode,uint16 multiple) external onlyOwner{
        _bonusMultiple[mode]=multiple;
    }

    function updateMaxMultiple(uint multiple) external onlyOwner{
        MaxMultiple=multiple;
    }
}