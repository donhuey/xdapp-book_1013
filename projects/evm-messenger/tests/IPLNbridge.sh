node orchestrator.js evm0 deploy
node orchestrator.js evm1 deploy
node orchestrator.js evm0 register_chain evm1
node orchestrator.js evm1 register_chain evm0
node orchestrator.js evm0 escrowFunds "From: evm0\nMsg: Funds deposited, payload sent to destination!" # escrowFunds on the origin chain
node orchestrator.js evm1 submit_vaa evm0 latest # submit the vaa and payload to the destination chain
node orchestrator.js evm1 matchBridgeRequest "From: evm1\nMsg: Hello World!" # matchBridgeRequest on the destination chain
node orchestrator.js evm0 submit_vaa evm1 latest # submit the vaa and payload to payliquidity provider on the origin chain
sleep 10
node orchestrator.js evm0 get_current_msg # return the deposit object in the origin chain
node orchestrator.js evm1 get_current_msg # return the LP's transaction on the destination chain