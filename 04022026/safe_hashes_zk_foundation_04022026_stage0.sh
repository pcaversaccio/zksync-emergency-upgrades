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
# See: https://github.com/safe-fndn/safe-smart-account/blob/a0a1d4292006e26c4dbd52282f4c932e1ffca40f/contracts/Safe.sol#L54-L57.
readonly SAFE_DOMAIN_SEPARATOR_TYPEHASH="0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218"
# => `keccak256("SafeMessage(bytes message)");`
# See: https://github.com/safe-fndn/safe-smart-account/blob/febab5e4e859e6e65914f17efddee415e4992961/contracts/libraries/SignMessageLib.sol#L12-L13.
readonly SAFE_MSG_TYPEHASH="0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca"

# EIP-712 domain parameters.
# => `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");`
readonly DOMAIN_SEPARATOR_TYPEHASH="0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f"
readonly NAME="EmergencyUpgradeBoard"
readonly VERSION="1"
readonly CHAIN_ID="1"
readonly VERIFYING_CONTRACT="0xECE8e30bFc92c2A8e11e6cb2e17B70868572E3f6"

# Emergency-upgrade-specific parameters.
# => `keccak256("ExecuteEmergencyUpgradeZKFoundation(bytes32 id)");`
readonly EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH="0xbc65a4e7edaf75c145d74b7c4e65a168cf6bce5e78f11e27fcd63ed0c62afacf"
#  => Set the calculated proposal ID here.
readonly PROPOSAL_ID="0xd43cd5f78cdd867d5a50faa742bfac7f46020df62180fb044419f339bd1d86fa"

# Calculate the Safe multisig domain hash.
safe_domain_hash=$(chisel eval "keccak256(abi.encode(bytes32($SAFE_DOMAIN_SEPARATOR_TYPEHASH), uint256($CHAIN_ID), address($SAFE_MULTISIG_ADDRESS)))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

# Calculate the EIP-712 message domain hash.
message_domain_hash=$(chisel eval "keccak256(abi.encode(bytes32($DOMAIN_SEPARATOR_TYPEHASH), keccak256(bytes('$NAME')), keccak256(bytes('$VERSION')), uint256($CHAIN_ID), address($VERIFYING_CONTRACT)))" |
	awk '/Data:/ {gsub(/\x1b\[[0-9;]*m/, "", $3); print $3}')

# Encode the message.
message=$(cast abi-encode "ExecuteEmergencyUpgradeZKFoundation(bytes32,bytes32)" \
	"$EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH" \
	"$PROPOSAL_ID")

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
