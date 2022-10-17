import { exec } from "child_process";
import fs from "fs";
import { ethers } from "ethers";
import {
    getEmitterAddressEth,
    parseSequenceFromLogEth,
} from "@certusone/wormhole-sdk";

import fetch from "node-fetch";
// import Structs from "./chains/evm/out/Structs.sol/Structs.json" assert {type: "json"};

async function main() {
    let config = JSON.parse(fs.readFileSync("./xdapp.config.json").toString());
    const _abiCoder = new ethers.utils.AbiCoder;
    const Signature = [
		"bytes32", 
		"bytes32", 
		"uint8", 
		"uint8"
    ]
    const VM = [
        "uint8",
		"uint32",
		"uint32",
		"uint16",
		"bytes32",
		"uint64",
		"uint8",
		"bytes",
		"uint32",
		"tuple(bytes32, bytes32, uint8, uint8)",
		"bytes32",
    ]


    console.log(
        `process.argv....`, process.argv
    );

    let network = config.networks[process.argv[2]];
    if (!network) {
        throw new Error("Network not defined in config file.");
    }
    
    if (process.argv[3] == "deploy") {
        if (network.type == "evm") {
            console.log(
                `Deploying EVM network: ${process.argv[2]} to ${network.rpc}`
            );
            // IPLNTEST // change contract name from messenger to IPLNTEST
            exec(
                `cd chains/evm && forge build && forge create --legacy --rpc-url ${network.rpc} --private-key ${network.privateKey} src/IPLNTEST.sol:Messenger && exit`,
                (err, out, errStr) => {
                    if (err) {
                        throw new Error(err);
                    }

                    if (out) {
                        console.log(out);
                        network.deployedAddress = out
                            .split("Deployed to: ")[1]
                            .split("\n")[0]
                            .trim();
                        network.emittedVAAs = []; //Resets the emittedVAAs
                        config.networks[process.argv[2]] = network;
                        fs.writeFileSync(
                            "./xdapp.config.json",
                            JSON.stringify(config, null, 4)
                        );
                    }
                }
            );
        } else {
            throw new Error("Invalid Network Type!");
        }
    } else if (process.argv[3] == "register_chain") {
        if (!network.deployedAddress) {
            throw new Error("Deploy to this network first!");
        }

        const targetNetwork = config.networks[process.argv[4]];
        if (!targetNetwork.deployedAddress) {
            throw new Error("Target Network not deployed yet!");
        }

        let emitterAddr;
        if (targetNetwork.type == "evm") {
            emitterAddr = Buffer.from(
                getEmitterAddressEth(targetNetwork.deployedAddress),
                "hex"
            );
        }

        if (network.type == "evm") {
            const signer = new ethers.Wallet(network.privateKey).connect(
                new ethers.providers.JsonRpcProvider(network.rpc)
            );

            const messenger = new ethers.Contract(
                network.deployedAddress,
                JSON.parse(
                    fs
                        .readFileSync(
                            "./chains/evm/out/IPLNTEST.sol/IPLN.json"
                        )
                        .toString()
                ).abi,
                signer
            );
            await messenger.registerApplicationContracts(
                targetNetwork.wormholeChainId,
                emitterAddr
            );

        }
        console.log(
            `Network(${process.argv[2]}) Registered Emitter: ${targetNetwork.deployedAddress} from Chain: ${process.argv[4]}`
        );
    } else if (process.argv[3] == "escrowFunds") {
        if (!network.deployedAddress) {
            throw new Error("Deploy to this network first!");
        }

        if (network.type == "evm") {
            const signer = new ethers.Wallet(network.privateKey).connect(
                new ethers.providers.JsonRpcProvider(network.rpc)
            );
            const messenger = new ethers.Contract(
                network.deployedAddress,
                JSON.parse(
                    fs
                        .readFileSync(
                            "./chains/evm/out/IPLNTEST.sol/IPLN.json"
                        )
                        .toString()
                ).abi,
                signer
            );
            const mssgString = ['0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1','0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1','1000'];

            const tx = await (
                await messenger.sendMsg(mssgString)
                // await messenger.sendMsg(Buffer.from(process.argv[4]))
                //lock the token using the escrowFunds
            ).wait();
            console.log('message was sent, and message object', tx);

            await new Promise((r) => setTimeout(r, 5000));
            const emitterAddr = getEmitterAddressEth(messenger.address);
            const seq = parseSequenceFromLogEth(tx, network.bridgeAddress);
            console.log(
                "Searching for: ",
                `${config.wormhole.restAddress}/v1/signed_vaa/${network.wormholeChainId}/${emitterAddr}/${seq}`
            );
            const vaaBytes = await (
                await fetch(
                    `${config.wormhole.restAddress}/v1/signed_vaa/${network.wormholeChainId}/${emitterAddr}/${seq}`
                )
            ).json();
            if (!network.emittedVAAs) {
                network.emittedVAAs = [vaaBytes.vaaBytes];
            } else {
                network.emittedVAAs.push(vaaBytes.vaaBytes);
            }
            config.networks[process.argv[2]] = network;
            fs.writeFileSync(
                "./xdapp.config.json",
                JSON.stringify(config, null, 2)
            );
            console.log(
                `Network(${process.argv[2]}) Emitted VAA: `,
                vaaBytes.vaaBytes
            );
        }
    } else if (process.argv[3] == "submit_vaa") {
        if (!network.deployedAddress) {
            throw new Error("Deploy to this network first!");
        }
        const targetNetwork = config.networks[process.argv[4]];
        const vaaBytes = isNaN(parseInt(process.argv[5]))
            ? targetNetwork.emittedVAAs.pop()
            : targetNetwork.emittedVAAs[parseInt(process.argv[5])];

        if (network.type == "evm") {
            const signer = new ethers.Wallet(network.privateKey).connect(
                new ethers.providers.JsonRpcProvider(network.rpc)
            );
            const messenger = new ethers.Contract(
                network.deployedAddress,
                JSON.parse(
                    fs
                        .readFileSync(
                            "./chains/evm/out/IPLNTEST.sol/IPLN.json"
                        )
                        .toString()
                ).abi,
                signer
            );
            // function base64ToHex(str) {
            //     const raw = atob(str);

            //     console.log("atob data in raw variable...",raw);
            //     let result = '';
            //     for (let i = 0; i < raw.length; i++) {
            //       const hex = raw.charCodeAt(i).toString(16);
            //       result += (hex.length === 2 ? hex : '0' + hex);
            //     }
            //     return ("0x"+result).toUpperCase();
            //   }
              
            //   console.log(base64ToHex("oAAABTUAAg=="));

            const bytesVersionOfVaa = Buffer.from(vaaBytes, "base64");
            console.log('bytesVersionOfVaa....', bytesVersionOfVaa);
            // console.log('hexVersionOfVaa....', base64ToHex(vaaBytes));

            console.log("Vaa byte output....", vaaBytes);
            // try to deconstruct bytesVersionOfVaa into readable data
            // console.log("trying to decode bytes version of vaa...", _abiCoder.decode(VM,vaaBytes) );
            const tx = await messenger.receiveEncodedMsg(
                Buffer.from(vaaBytes, "base64")
                // This is where the matchBridgeRequest / ProcessVaaAndExecutePayload workflow will be triggered
            );
            console.log(`Submitted VAA: ${vaaBytes}\nTX: ${tx.hash}`);
        }
    } else if (process.argv[3] == "get_current_msg") {
        if (!network.deployedAddress) {
            throw new Error("Deploy to this network first!");
        }
        if (network.type == "evm") {
            const signer = new ethers.Wallet(network.privateKey).connect(
                new ethers.providers.JsonRpcProvider(network.rpc)
            );
            const messenger = new ethers.Contract(
                network.deployedAddress,
                JSON.parse(
                    fs
                        .readFileSync(
                            "./chains/evm/out/IPLNTEST.sol/IPLN.json"
                        )
                        .toString()
                ).abi,
                signer
            );
            console.log(
                `${process.argv[2]} Current Msg: `,
                await messenger.getCurrentMsg()
            );
        }
    } else {
        throw new Error("Unkown command!");
    }
}
main();
