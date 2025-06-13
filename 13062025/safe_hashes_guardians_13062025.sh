#!/usr/bin/env bash

########################
# Don't trust, verify! #
########################

# @license GNU Affero General Public License v3.0 only
# @author pcaversaccio

# Enable strict error handling:
# -E: Inherit `ERR` traps in functions and subshells.
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error and exit.
# -o pipefail: Return the exit status of the first failed command in a pipeline.
set -Eeuo pipefail

# Enable debug mode if the environment variable `DEBUG` is set to `true`.
if [[ "${DEBUG:-false}" == "true" ]]; then
	# Print each command before executing it.
	set -x
fi

# Utility function to format the hash (keep `0x` lowercase, rest uppercase).
format_hash() {
	local hash=$1
	local prefix="${hash:0:2}"
	local rest="${hash:2}"
	echo "${prefix,,}${rest^^}"
}

# => Set your Safe multisig address here.
readonly SAFE_MULTISIG_ADDRESS="0xCe7a3dFcc35602155809920Ff65e093aa726f6cf"

# Set the Safe type hash constants.
# => `keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");`
# See: https://github.com/safe-global/safe-smart-account/blob/a0a1d4292006e26c4dbd52282f4c932e1ffca40f/contracts/Safe.sol#L54-L57.
readonly SAFE_DOMAIN_SEPARATOR_TYPEHASH="0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218"
# => `keccak256("SafeMessage(bytes message)");`
# See: https://github.com/safe-global/safe-smart-account/blob/febab5e4e859e6e65914f17efddee415e4992961/contracts/libraries/SignMessageLib.sol#L12-L13.
readonly SAFE_MSG_TYPEHASH="0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca"

# EIP-712 domain parameters.
# => `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");`
# See here: https://etherscan.io/address/0x600dA620Ab29F41ABC6596a15981e14cE58c86b8.
readonly DOMAIN_SEPARATOR_TYPEHASH="0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f"
readonly NAME="Guardians"
readonly VERSION="1"
readonly CHAIN_ID="1"
readonly VERIFYING_CONTRACT="0x600da620ab29f41abc6596a15981e14ce58c86b8"

# Cancel-specific parameters.
# => `keccak256("CancelL2GovernorProposal(uint256 l2ProposalId,address l2GovernorAddress,uint256 l2GasLimit,uint256 l2GasPerPubdataByteLimit,address refundRecipient,uint256 txMintValue,uint256 nonce)");`
readonly CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH="0x8b11acd0ef1224d9667d505a66919340beb45aa850b9ddef03c49b2b66993146"
readonly L2_PROPOSAL_ID="62921954496791164991088292844527972033503604235062526266434445973055965160650"
readonly L2_GOVERNOR_ADDRESS="0xb83ff6501214ddf40c91c9565d095400f3f45746"
readonly L2_GAS_LIMIT="30000000"
readonly L2_GAS_PER_PUBDATA_BYTE_LIMIT="800"
readonly REFUNDRECIPIENT="0xf378708b88841abb63e2316e4fc8f29469bee885"
readonly TX_MINT_VALUE="20000000000000000"
readonly NONCE="0"

# Calculate the Safe multisig domain hash.
safe_domain_hash=$(chisel eval "keccak256(abi.encode(bytes32($SAFE_DOMAIN_SEPARATOR_TYPEHASH), uint256($CHAIN_ID), address($SAFE_MULTISIG_ADDRESS)))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

# Calculate the EIP-712 message domain hash.
message_domain_hash=$(chisel eval "keccak256(abi.encode(bytes32($DOMAIN_SEPARATOR_TYPEHASH), keccak256(bytes('$NAME')), keccak256(bytes('$VERSION')), uint256($CHAIN_ID), address($VERIFYING_CONTRACT)))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

# Encode the message.
message=$(cast abi-encode "CancelL2GovernorProposal(bytes32,uint256,address,uint256,uint256,address,uint256,uint256)" \
	"$CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH" \
	"$L2_PROPOSAL_ID" \
	"$L2_GOVERNOR_ADDRESS" \
	"$L2_GAS_LIMIT" \
	"$L2_GAS_PER_PUBDATA_BYTE_LIMIT" \
	"$REFUNDRECIPIENT" \
	"$TX_MINT_VALUE" \
	"$NONCE")

# Hash the message.
hashed_message=$(cast keccak "$message")

# Calculate the Safe message.
safe_msg=$(chisel eval "keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), bytes32($message_domain_hash), bytes32($hashed_message)))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

# Calculate the message hash.
message_hash=$(chisel eval "keccak256(abi.encode(bytes32($SAFE_MSG_TYPEHASH), keccak256(abi.encode(bytes32($safe_msg)))))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

# Calculate the Safe message hash.
safe_msg_hash=$(chisel eval "keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), bytes32($safe_domain_hash), bytes32($message_hash)))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

echo "Safe message: $safe_msg"
echo "Safe message hash: $safe_msg_hash"
echo "Domain hash: $(format_hash $safe_domain_hash)"
echo "Message hash: $(format_hash $message_hash)"
