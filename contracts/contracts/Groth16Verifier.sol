// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    // Scalar field size
    uint256 constant r    = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q   = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax  = 11382477024738729271055270785309867280305381254262299934130808668928277886027;
    uint256 constant alphay  = 13793255252709522358653917727077637381033544702817027461662113548578316431642;
    uint256 constant betax1  = 4480802243588367679454885673882721999399673206907596849317485214232036241487;
    uint256 constant betax2  = 6836945306999098927350115772555610444573407405151870746280832378169542001895;
    uint256 constant betay1  = 202818063746663014903702209454080060356386802328209630267331891031675280048;
    uint256 constant betay2  = 14617645176901870657297505265654140294498696221527982783702195806614019435100;
    uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 = 10342161486456137811696717134835418009478733636360738671814613042082246868639;
    uint256 constant deltax2 = 10383267093536625278053549075342082419956861435965014100701572693333925961464;
    uint256 constant deltay1 = 3475626764731537189541976679061225513100828994061694430330820764439208662785;
    uint256 constant deltay2 = 17205543232169253921868733991812085518033836335836908550110638724736894844442;

    
    uint256 constant IC0x = 14930293257806847874808549568005947247261888715703334399033468964412060965815;
    uint256 constant IC0y = 9218801092232508067237687940679119163619247727588769417564320592082683507587;
    
    uint256 constant IC1x = 3741884045201392010317937152152846452821440929632348907233750866791460192173;
    uint256 constant IC1y = 5674553850003578708591572549557065312066070611435613670967158969158860102641;
    
    uint256 constant IC2x = 21812703480124473296295117946126273214023633179834349017038173112856342930005;
    uint256 constant IC2y = 948592003100213176227044599778780019339105802827419102133314092673008302725;
    
    uint256 constant IC3x = 19686355713351218419027986707160874652648442892225811076806910989378965533373;
    uint256 constant IC3y = 20933392669489799638649921805433752576803876968641069487608311972255564632275;
    
    uint256 constant IC4x = 16021655828383749612716138438044153448291997159974938610168153006859656432900;
    uint256 constant IC4y = 15074569768068320494915063569620469936002935760975224290455444766300991352262;
    
    uint256 constant IC5x = 7740226217332175224992676783050357436108370422914375574319916412770371431859;
    uint256 constant IC5y = 5954413192772634661296122744857952718201968775229977306220823529890202307654;
    
    uint256 constant IC6x = 2678866385225421457129672836417987204522963999339581925086401688007512561052;
    uint256 constant IC6y = 2727591109168673173499734212578828830503252107130053664941128116206882350363;
    
    uint256 constant IC7x = 16357923164288363331017321738648459632249280327009453708320703543094146426118;
    uint256 constant IC7y = 13455008165893028754868874014059159899056374919089446809079808904715963233463;
    
    uint256 constant IC8x = 18763114311665918382822721037205649677382409834548456790383173960830545123797;
    uint256 constant IC8y = 209229479396008974617596264349223916817208087092286128553924641920178666056;
    
    uint256 constant IC9x = 20008577570143768178747332823484276799593967930871448945066053566764126924559;
    uint256 constant IC9y = 4200215658730529239470361424722476468502102179384371159873033079787223153669;
    
    uint256 constant IC10x = 14841482923869736229420038223324931441490669141270916671315881858434057888306;
    uint256 constant IC10y = 7725321094532434918139959765245672991969347716399163890034361143771794287646;
    
    uint256 constant IC11x = 2780449404512290621344962941969340899427537542734828615092583617712701823027;
    uint256 constant IC11y = 10034570640591481260331337467435533128271193483114413610470026213351498459468;
    
 
    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 896;

    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[11] calldata _pubSignals) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, r)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }
            
            // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x, y, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x)
                mstore(add(mIn, 32), y)
                mstore(add(mIn, 64), s)

                success := staticcall(sub(gas(), 2000), 7, mIn, 96, mIn, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 64), mload(pR))
                mstore(add(mIn, 96), mload(add(pR, 32)))

                success := staticcall(sub(gas(), 2000), 6, mIn, 128, pR, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                mstore(_pVk, IC0x)
                mstore(add(_pVk, 32), IC0y)

                // Compute the linear combination vk_x
                
                g1_mulAccC(_pVk, IC1x, IC1y, calldataload(add(pubSignals, 0)))
                
                g1_mulAccC(_pVk, IC2x, IC2y, calldataload(add(pubSignals, 32)))
                
                g1_mulAccC(_pVk, IC3x, IC3y, calldataload(add(pubSignals, 64)))
                
                g1_mulAccC(_pVk, IC4x, IC4y, calldataload(add(pubSignals, 96)))
                
                g1_mulAccC(_pVk, IC5x, IC5y, calldataload(add(pubSignals, 128)))
                
                g1_mulAccC(_pVk, IC6x, IC6y, calldataload(add(pubSignals, 160)))
                
                g1_mulAccC(_pVk, IC7x, IC7y, calldataload(add(pubSignals, 192)))
                
                g1_mulAccC(_pVk, IC8x, IC8y, calldataload(add(pubSignals, 224)))
                
                g1_mulAccC(_pVk, IC9x, IC9y, calldataload(add(pubSignals, 256)))
                
                g1_mulAccC(_pVk, IC10x, IC10y, calldataload(add(pubSignals, 288)))
                
                g1_mulAccC(_pVk, IC11x, IC11y, calldataload(add(pubSignals, 320)))
                

                // -A
                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), mod(sub(q, calldataload(add(pA, 32))), q))

                // B
                mstore(add(_pPairing, 64), calldataload(pB))
                mstore(add(_pPairing, 96), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))

                // alpha1
                mstore(add(_pPairing, 192), alphax)
                mstore(add(_pPairing, 224), alphay)

                // beta2
                mstore(add(_pPairing, 256), betax1)
                mstore(add(_pPairing, 288), betax2)
                mstore(add(_pPairing, 320), betay1)
                mstore(add(_pPairing, 352), betay2)

                // vk_x
                mstore(add(_pPairing, 384), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 416), mload(add(pMem, add(pVk, 32))))


                // gamma2
                mstore(add(_pPairing, 448), gammax1)
                mstore(add(_pPairing, 480), gammax2)
                mstore(add(_pPairing, 512), gammay1)
                mstore(add(_pPairing, 544), gammay2)

                // C
                mstore(add(_pPairing, 576), calldataload(pC))
                mstore(add(_pPairing, 608), calldataload(add(pC, 32)))

                // delta2
                mstore(add(_pPairing, 640), deltax1)
                mstore(add(_pPairing, 672), deltax2)
                mstore(add(_pPairing, 704), deltay1)
                mstore(add(_pPairing, 736), deltay2)


                let success := staticcall(sub(gas(), 2000), 8, _pPairing, 768, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F
            
            checkField(calldataload(add(_pubSignals, 0)))
            
            checkField(calldataload(add(_pubSignals, 32)))
            
            checkField(calldataload(add(_pubSignals, 64)))
            
            checkField(calldataload(add(_pubSignals, 96)))
            
            checkField(calldataload(add(_pubSignals, 128)))
            
            checkField(calldataload(add(_pubSignals, 160)))
            
            checkField(calldataload(add(_pubSignals, 192)))
            
            checkField(calldataload(add(_pubSignals, 224)))
            
            checkField(calldataload(add(_pubSignals, 256)))
            
            checkField(calldataload(add(_pubSignals, 288)))
            
            checkField(calldataload(add(_pubSignals, 320)))
            

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
             return(0, 0x20)
         }
     }
 }
