//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Wormhole/IWormhole.sol";

contract Messenger {
    bytes private current_msg;
    address private wormhole_core_bridge_address = address(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550);
    IWormhole core_bridge = IWormhole(wormhole_core_bridge_address);
    uint32 nonce = 0;
    mapping(uint16 => bytes32) _applicationContracts;
    address owner;
    mapping(bytes32 => bool) _completedMessages;
    event payLoadTracker(string _functionThatWasExecuted); // emit a message after calling the wormwhole core contract


    constructor(){
        owner = msg.sender;
    }

    struct matchMade {
                        address originCurrencyAddr; // address or bytes for multichain
                        address destinationCurrencyAddr; // address or bytes for multichain
                        uint amount;
                    }

    function sendMsg(matchMade memory str) public returns (uint64 sequence) {
        matchMade memory responseObject = str;
        emit payLoadTracker("message sent");
        bytes memory abiEncodedParameters = abi.encode(responseObject); // encoding the most recent aggreementToBridgeReq


        sequence = core_bridge.publishMessage(nonce, abiEncodedParameters, 1);
        nonce = nonce+1;
    }

    function receiveEncodedMsg(bytes memory encodedMsg) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = core_bridge.parseAndVerifyVM(encodedMsg);
        
        //1. Check Wormhole Guardian Signatures
        //  If the VM is NOT valid, will return the reason it's not valid
        //  If the VM IS valid, reason will be blank
        require(valid, reason);

        //2. Check if the Emitter Chain contract is registered
        require(_applicationContracts[vm.emitterChainId] == vm.emitterAddress, "Invalid Emitter Address!");
    
        //3. Check that the message hasn't already been processed
        require(!_completedMessages[vm.hash], "Message already processed");
        _completedMessages[vm.hash] = true;

        //Do the thing
        current_msg = vm.payload;
        emit payLoadTracker("message received");

    }

    function getCurrentMsg() public view returns (bytes memory){
        return current_msg;
    }
    /**
        Registers it's sibling applications on other chains as the only ones that can send this instance messages
     */
    function registerApplicationContracts(uint16 chainId, bytes32 applicationAddr) public {
        require(msg.sender == owner, "Only owner can register new chains!");
        _applicationContracts[chainId] = applicationAddr;
    }
}
