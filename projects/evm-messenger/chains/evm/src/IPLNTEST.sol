// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "/Users/donhuey/Desktop/iplnTestcase/xdapp-book/projects/evm-messenger/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "/Users/donhuey/Desktop/iplnTestcase/xdapp-book/projects/evm-messenger/node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./Wormhole/IWormhole.sol";
import "./Wormhole/Structs.sol";


//this contract is responsible for escrowing & releasing the funds on both chains. 
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint) external;
}

contract IPLN is Ownable{

                    // bool and modefier  to guard against reentrancy
                    bool internal locked; 
                    modifier noReentrant() {
                    require(!locked, "No re-entrancy");
                    locked = true;
                    _;
                    locked = false;
                    }

////////////////////
// STATE PARAMETERS
///////////////////
                    address private wormWholeCoreAddress = address(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550);

                    IWormhole public _wormWhole = IWormhole(wormWholeCoreAddress);
                    uint reqToBridgeOutId;
                    uint aggreementToBridgeReqId;
                    mapping(uint => Deposit) reqToBridgeOut; // Keep track of every deposit made...
                    mapping(uint => matchMade) aggreementToBridgeReq; // Keep track of every incoming reqToBridgeOut
                    mapping(uint16 => bytes32) _applicationContracts;
                    mapping(bytes32 => bool) _completedMessages;
                    string private current_msg;
                    uint32 nonce = 0;
                    //event that emmits message for every offchain call
                    event mesageSent(uint _sequence, string _message); // emit a message after calling the wormwhole core contract
                    event payLoadTracker(uint _payLoadId, string _functionThatWasExecuted); // emit a message after calling the wormwhole core contract
                    event relayObjectTracker(uint _payLoadId, string _functionThatWasExecuted, relayObject _objectToRelay ); // emit message after calling each wormwholecontract


////////////////////
// STRUCTS -- should  move into the Structs.sol file
///////////////////       

                    // this struct will be passed cross chain through VAA. the payload Id will give context to each contract and determine what function gets called  
                    struct relayObject {
                        uint _payLoadId; // payLoadId: this will determine how the relay object gets unpacked and what function gets called.
                        address _Depositor; // address or bytes for multichain wallet address of user on the origin chain
                        address _liquidityRelayer; //or bytes Relayer's wallet address on the origin chain
                        uint _originChain; //origin  chain id 
                        uint _destinationChain; // destinantion chain id
                        address _originCurrencyAddr; // currency address on origin chain
                        address _destinationCurrencyAddr;  // address or bytes for multichain currency address on destinantion chain
                        address _destinationWalletAddr;  // address or bytes for multichain Users wallet address on destination chain
                        uint _depositAmount; // amount of money deposited on origin chain by the user
                        uint _minExpectedAmount; // a percentage of the deposit amout, this is the minimum expected amount by the user on the destination chain
                        uint _reqToBridgeOutId; // mapping id for deposit object
                        uint _aggreementToBridgeReq; // mapping for relayers deposit id on the destination chain
                    }

                    // This struct tracks user funds escrowed on the origin chain
                    struct Deposit {
                        address Depositor; // address or bytes for multichain
                        uint destinationChain;
                        address originCurrencyAddr;
                        address destinationCurrencyAddr;  // address or bytes for multichain
                        address destinationWalletAddr;  // address or bytes for multichain
                        uint amount;
                        uint expiery;
                        bool tradeCompleted;
                    }
                    // This struct tracks liquidity provided by relayers on the destination chain
                    struct matchMade {
                        address liquidityRelayer; //or bytes
                        // uint destinationChain;
                        address destinationCurrencyAddr; // address or bytes for multichain
                        uint amount;
                        uint profitAmount;
                        uint reqToBridgeOutId;
                        uint functionCallNumber;
                    }

////////////////////
// Helper Functions
///////////////////                   

                    // returns the msg.sender's allowance balance to this contract given an erc20 address
                    function GetThisContractAllowance(IERC20 _Coin) public view returns(uint256){
                        return _Coin.allowance(msg.sender, address(this));
                    }

                   // This function escrows users funds on the origin chain. 
                   // this is the first important step in the process of bridging
                    function escrowFunds(
                        uint destinationChain,
                        address originCurrencyAddr,
                        address destinationCurrencyAddr, // address or bytes for multichain
                        address destinationWalletAddr, // address or bytes for multichain
                        uint amount,
                        uint expiery) public payable returns (bool) {
                                // IERC20 originCurrency = IERC20(originCurrencyAddr);
                                // require(amount <= GetThisContractAllowance(originCurrency),"approve enough token");
                                // originCurrency.transferFrom(msg.sender, address(this), amount);
                                // require(originCurrency.balanceOf(address(this)) >= amount, "transfer_failed");
                                reqToBridgeOut[reqToBridgeOutId] =Deposit(msg.sender, destinationChain,originCurrencyAddr,destinationCurrencyAddr,destinationWalletAddr,amount,expiery,false);
                                reqToBridgeOutId +=1;

                                // next step is to encode required parameters 
                                relayObject memory responseObject;

                                responseObject._payLoadId = 1; // payLoadId: this will determine how the relay object gets unpacked and what function gets called.
                                responseObject._Depositor = address(msg.sender); // address or bytes for multichain wallet address of user on the origin chain
                                responseObject._destinationChain = destinationChain; // destinantion chain id comes from user input.
                                responseObject._originCurrencyAddr = originCurrencyAddr; // currency address on origin chain
                                responseObject._destinationCurrencyAddr = destinationCurrencyAddr;  // address or bytes for multichain currency address on destinantion chain
                                responseObject._destinationWalletAddr = destinationWalletAddr;  // address or bytes for multichain Users wallet address on destination chain
                                responseObject._depositAmount = amount; // amount of money deposited on origin chain by the user
                                // This should be calculated based on a fee mechanisim, but we can leave it equal to the deposit amount for now
                                responseObject._minExpectedAmount = amount; // a percentage of the deposit amout, this is the minimum expected amount by the user on the destination chain

                                responseObject._reqToBridgeOutId = reqToBridgeOutId-1; // mapping id for deposit object

                            
                                bytes memory abiEncodedParameters = abi.encode(responseObject); // encoding the most recent aggreementToBridgeReq
                                emitMyMessage(abiEncodedParameters); // emmit new vaa by sending encoded data to the core contract.
                                emit relayObjectTracker(0,"escrowed funds", responseObject); // emit message after calling each wormwholecontract

                                return true;
                    }


                // matchVaultFunds() executes escrow function that locks a liquidity relayers funds.
                function matchBridgeRequest( relayObject memory _relayObject) public noReentrant payable returns(bool) {
                        
                        // lets instanciate Ierc20 for evm contracts here.
                        // IERC20 destinationCurrency = IERC20(_relayObject._destinationCurrencyAddr);
                        // require(_relayObject._minExpectedAmount <= GetThisContractAllowance(destinationCurrency),"approve enough token");
                        // destinationCurrency.transferFrom(msg.sender, _relayObject._destinationWalletAddr, _relayObject._minExpectedAmount);
                        // require(destinationCurrency.balanceOf( _relayObject._destinationWalletAddr) >= _relayObject._minExpectedAmount, "transfer_failed");
                        // create new object that keeps track of current transaction details. this will also be sent back to the origin contract for context.
                        aggreementToBridgeReq[aggreementToBridgeReqId] = matchMade(msg.sender,_relayObject._destinationCurrencyAddr, _relayObject._minExpectedAmount,_relayObject._depositAmount,_relayObject._reqToBridgeOutId,2);
                        aggreementToBridgeReqId +=1;
                       
                        // next step is to encode required parameters and update the message object with new data 
                         relayObject memory responseObject = _relayObject;

                        responseObject._payLoadId = 2; // payLoadId: this will determine how the relay object gets unpacked and what function gets called.
                        responseObject._liquidityRelayer = address(msg.sender); //or bytes Relayer's wallet address on the origin chain
                        responseObject._aggreementToBridgeReq = aggreementToBridgeReqId-1; // mapping for relayers deposit id on the destination chain
                       
                        bytes memory abiEncodedParameters = abi.encode(responseObject); // encoding the most recent aggreementToBridgeReq
                        emitMyMessage(abiEncodedParameters); // emmit new vaa by sending encoded data to the core contract.
                        emit relayObjectTracker(1,"matched Bridge Request", responseObject); // emit message after calling each wormwholecontract
                        return true;
                    }


                // this function sends funds to the Liquidity providers originchain wallet address
                function payLiquidityRelayer( relayObject memory _relayObject) public noReentrant payable returns(bool) {
             
                        // make sure trade has not already been made
                        require(reqToBridgeOut[_relayObject._reqToBridgeOutId].tradeCompleted == false, "replay_protection");
                        reqToBridgeOut[_relayObject._reqToBridgeOutId].tradeCompleted = true;
                        // lets instanciate Ierc20 for evm contracts here.
                        // IERC20 originCurrency = IERC20(reqToBridgeOut[_relayObject._reqToBridgeOutId].originCurrencyAddr);
                        //send money to relayer
                        // originCurrency.transferFrom(address(this), _relayObject._liquidityRelayer, reqToBridgeOut[_relayObject._reqToBridgeOutId].amount);
                        // require(originCurrency.balanceOf(_relayObject._liquidityRelayer) >= reqToBridgeOut[_relayObject._reqToBridgeOutId].amount, "transfer_failed");
                        emit relayObjectTracker(2,"paid Liquidity Relayer", _relayObject); // emit message after calling each wormwholecontract
                        return true;
                    }

                // this is the entry point for incoming messages on this contract.
                // PayloadId will give context and determine what stage and function is required complete trade
                 function ProcessVaaAndExecutePayload(bytes memory VAA) public {
                        // first step is to verify the recieved vaa message 
                        (IWormhole.VM memory vm) = processAndVerifyMyMessage(VAA);
                        // next we can initialize the properties we need 
                        bytes memory verifiedMessage = vm.payload;
                        uint emitterChainId = vm.emitterChainId;
                        bytes32 emitterAddress = vm.emitterAddress;

                        // Skipped Step, Unpack addresses into evm or non evm address datatypes from bytes

                        (relayObject memory unpackedVaa) = abi.decode(verifiedMessage, ( relayObject));

                        if (unpackedVaa._payLoadId == 1){
                            unpackedVaa._originChain = emitterChainId;
                            require(matchBridgeRequest(unpackedVaa), 'matchBridgeRequestFailed');
                            // emit payLoadTracker(1,"matchBridgeRequest");

                        }else if (unpackedVaa._payLoadId == 2) {
                            unpackedVaa._destinationChain = emitterChainId; // instantiating the destination, we can check to verify it is coming from a trusted source
                            require(payLiquidityRelayer(unpackedVaa), 'payLiquidityRelayerFailed');
                            // emit payLoadTracker(2,"payLiquidityRelayer");

                        }
                        // else{

                        // }


                 }                


// /////////////////////////////////////////////////////////////////////////
// /////////////////////////////////////////////////////////////////////////
// /////////////////////////////////////////////////////////////////////////
// IMPLIMENTATION MECHANNISM OF SENDING AND RECIEVING AND VERIFYING VAA MESSAGES
// /////////////////////////////////////////////////////////////////////////
// /////////////////////////////////////////////////////////////////////////
// /////////////////////////////////////////////////////////////////////////

// address(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550)
                    constructor()  payable{
                                
                                }

// /////////////////////////////////////////////////////////////////////////
// RECIVE VAA MESSAGES FROM RELAYERS
// /////////////////////////////////////////////////////////////////////////


                mapping (uint16  => bytes32) public myTrustedContracts;
                mapping (bytes32 => bool) public processedMessages;
                mapping (bytes => address) public parseIntendedRecipient;


            // Verification accepts a single VAA, and is publicly callable.
            function processAndVerifyMyMessage(bytes memory VAA) public returns(IWormhole.VM memory) {
                // This call accepts single VAAs and headless VAAs
                (IWormhole.VM memory vm, bool valid, string memory reason) =
                    // core_bridge.parseAndVerifyVM(VAA);
                    _wormWhole.parseAndVerifyVM(VAA);

                // Ensure core contract verification succeeded.
                require(valid, reason);

                // Ensure the emitterAddress of this VAA is a trusted address
                // require(myTrustedContracts[vm.emitterChainId] ==
                //     vm.emitterAddress, "Invalid Emitter Address!");


                require(_applicationContracts[vm.emitterChainId] == vm.emitterAddress, "Invalid Emitter Address!");

                // Check that the VAA hasn't already been processed (replay protection)
                // require(!processedMessages[vm.hash], "Message already processed");

                require(!_completedMessages[vm.hash], "Message already processed");
                    _completedMessages[vm.hash] = true;

                // Check that the contract which is processing this VAA is the intendedRecipient
                // If the two aren't equal, this VAA may have bypassed its intended entrypoint.
                // This exploit is referred to as 'scooping'.

                // require(parseIntendedRecipient(vm.payload) == msg.sender);

                // Add the VAA to processed messages so it can't be replayed
                processedMessages[vm.hash] = true;


                // The message content can now be trusted.

                return (vm);

                    

                // doBusinessLogic(vm.payload)
            }

// /////////////////////////////////////////////////////////////////////////
// SEND MESSAGES TO GUARDIAN NETWORK
// /////////////////////////////////////////////////////////////////////////


            // This function defines a super simple Wormhole 'module'.
            // A module is just a piece of code which knows how to emit a composable message
            // which can be utilized by other contracts.
            // function emitMyMessage(address intendedRecipient, uint32 nonce)
            function emitMyMessage(bytes memory str)
                    public returns (uint64 sequence) {

                // Nonce is passed though to the core bridge.
                // This allows other contracts to utilize it for batching or processing.

                // intendedRecipient is key for composability!
                // This field will allow the destination contract to enforce
                // that the correct contract is submitting this VAA.

                // 1 is the consistency level,
                // this message will be emitted after only 1 block
                // sequence = core_bridge.publishMessage(nonce, "My Message to " + intendedRecipient, 1);
                sequence = _wormWhole.publishMessage(nonce, str , 1);
                nonce = nonce+1;

                emit mesageSent(sequence, "message_sent");

                // The sequence is passed back to the caller, which can be useful relay information.
                // Relaying is not done here, because it would 'lock' others into the same relay mechanism.
            }


            function getCurrentMsg() public view returns (string memory){
                    return current_msg;
                }
                /**
                    Registers it's sibling applications on other chains as the only ones that can send this instance messages
                */
                function registerApplicationContracts(uint16 chainId, bytes32 applicationAddr) public onlyOwner{
                    // require(msg.sender == owner, "Only owner can register new chains!");
                    _applicationContracts[chainId] = applicationAddr;
                }



}


// /////////////////////////////////////////////////////////////////////////
// TODOS AND QUESTIONS FOR JUMP TEAM
// /////////////////////////////////////////////////////////////////////////
// IF I HAVE A BUNCH OF CONTRACTS DEPLOYED ON DIFFERENT CHAINS, HOW DO I SPECIFY DESTINATION CHAIN AND DESTINANTION CONTRACT IN MY PAYLOAD
// ALSO HOW DO I SPECIFY THE FUNCTION TO CALL TO THE RELAYERS