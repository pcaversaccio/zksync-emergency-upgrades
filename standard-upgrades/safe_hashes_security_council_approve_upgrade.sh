#!/usr/bin/env bash

########################
# Don't trust, verify! #
########################

# @license GNU Affero General Public License v3.0 only
# @author pcaversaccio
# @author Stanislav Bezkorovainyi

# Shows what a Security Council member Safe signs to approve a standard protocol upgrade
# via `SecurityCouncil.approveUpgradeSecurityCouncil(id, signers, signatures)`.
# See: https://github.com/zksync-association/zk-governance/blob/master/l1-contracts/src/SecurityCouncil.sol.
#
# The Security Council checks an EIP-712 signature of `ApproveUpgradeSecurityCouncil(bytes32 id)`
# (domain `SecurityCouncil`, version `1`) from each member. A member is a Safe, so its owners
# sign an off-chain `SafeMessage` whose `message` is that EIP-712 digest. `id` is the
# `ProtocolUpgradeHandler` proposal ID, `keccak256(abi.encode(UpgradeProposal))`.
#
# All hashes are computed locally. With `--rpc-url`, the script also checks that the Safe is
# a Security Council member, shows the upgrade's state in the `ProtocolUpgradeHandler` (it
# must be `Waiting` to be approved), and cross-checks the Safe message hash against the Safe.
#
# Usage:
#   ./safe_hashes_security_council_approve_upgrade.sh --member-safe <address> --proposal-id <bytes32> \
#       [--security-council <address>] [--chain-id <id>] [--rpc-url <url>]
#
# The defaults of `--security-council` and `--chain-id` are the mainnet `SecurityCouncil` and 1.

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
	echo "0x$(echo "${hash:2}" | tr '[:lower:]' '[:upper:]')"
}

usage() {
	sed -n '/^# Usage:/,/^# The defaults of/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 1
}

die() {
	echo "Error: $*" >&2
	exit 1
}

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
readonly NAME="SecurityCouncil"
readonly VERSION="1"

# Upgrade-approval-specific parameters.
# => `keccak256("ApproveUpgradeSecurityCouncil(bytes32 id)");`
readonly APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH="0xc91a90b2153b64f9f68784c8eeb8c2bc7a62d3f153fcb15e9fbf277999d61f60"

# The `IProtocolUpgradeHandler.UpgradeState` enum.
readonly UPGRADE_STATES=(None LegalVetoPeriod Waiting ExecutionPending Ready Expired Done)

SECURITY_COUNCIL="0x59195219d1176E42f8e607e9AC114926D47f9035"
CHAIN_ID="1"
MEMBER_SAFE="" PROPOSAL_ID="" RPC_URL=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--member-safe)
		MEMBER_SAFE="$2"
		shift 2
		;;
	--proposal-id)
		PROPOSAL_ID="$2"
		shift 2
		;;
	--security-council)
		SECURITY_COUNCIL="$2"
		shift 2
		;;
	--chain-id)
		CHAIN_ID="$2"
		shift 2
		;;
	--rpc-url)
		RPC_URL="$2"
		shift 2
		;;
	-h | --help) usage ;;
	*) die "unknown argument $1" ;;
	esac
done
[[ -n "$MEMBER_SAFE" && -n "$PROPOSAL_ID" ]] || usage
[[ "$PROPOSAL_ID" =~ ^0x[0-9a-fA-F]{64}$ ]] || die "--proposal-id must be 32 bytes of 0x-prefixed hex"
[[ "$CHAIN_ID" =~ ^[0-9]+$ ]] || die "--chain-id must be a decimal number"

call() {
	cast call "$@" --rpc-url "$RPC_URL"
}

MEMBER_SAFE=$(cast to-check-sum-address "$MEMBER_SAFE")
SECURITY_COUNCIL=$(cast to-check-sum-address "$SECURITY_COUNCIL")

# Calculate the Safe multisig domain hash.
safe_domain_hash=$(cast keccak "$(cast abi-encode "f(bytes32,uint256,address)" "$SAFE_DOMAIN_SEPARATOR_TYPEHASH" "$CHAIN_ID" "$MEMBER_SAFE")")

# Calculate the EIP-712 message domain hash.
message_domain_hash=$(cast keccak "$(cast abi-encode "f(bytes32,bytes32,bytes32,uint256,address)" \
	"$DOMAIN_SEPARATOR_TYPEHASH" "$(cast keccak "$NAME")" "$(cast keccak "$VERSION")" "$CHAIN_ID" "$SECURITY_COUNCIL")")

# Hash the message.
hashed_message=$(cast keccak "$(cast abi-encode "ApproveUpgradeSecurityCouncil(bytes32,bytes32)" \
	"$APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH" "$PROPOSAL_ID")")

# Calculate the Safe message (the EIP-712 digest the Security Council checks).
safe_msg=$(cast keccak "$(cast concat-hex 0x1901 "$message_domain_hash" "$hashed_message")")

# Calculate the message hash.
message_hash=$(cast keccak "$(cast abi-encode "f(bytes32,bytes32)" "$SAFE_MSG_TYPEHASH" "$(cast keccak "$(cast abi-encode "f(bytes32)" "$safe_msg")")")")

# Calculate the Safe message hash.
safe_msg_hash=$(cast keccak "$(cast concat-hex 0x1901 "$safe_domain_hash" "$message_hash")")

if [[ -n "$RPC_URL" ]]; then
	[[ "$(cast chain-id --rpc-url "$RPC_URL")" == "$CHAIN_ID" ]] || die "the RPC is not for chain $CHAIN_ID"

	# The members are a public array, so read it until the getter reverts.
	is_member="false"
	i=0
	while member=$(call "$SECURITY_COUNCIL" "members(uint256)(address)" "$i" 2>/dev/null); do
		if [[ "$(echo "$member" | tr '[:upper:]' '[:lower:]')" == "$(echo "$MEMBER_SAFE" | tr '[:upper:]' '[:lower:]')" ]]; then
			is_member="true"
		fi
		i=$((i + 1))
	done
	[[ "$is_member" == "true" ]] || die "$MEMBER_SAFE is not a member of the Security Council $SECURITY_COUNCIL"

	onchain_safe_msg_hash=$(call "$MEMBER_SAFE" "getMessageHash(bytes)(bytes32)" "$(cast abi-encode "f(bytes32)" "$safe_msg")")
	[[ "$(echo "$onchain_safe_msg_hash" | tr '[:upper:]' '[:lower:]')" == "$safe_msg_hash" ]] ||
		die "Safe message hash mismatch: computed $safe_msg_hash, the Safe returned $onchain_safe_msg_hash"

	protocol_upgrade_handler=$(call "$SECURITY_COUNCIL" "PROTOCOL_UPGRADE_HANDLER()(address)")
	upgrade_state=$(call "$protocol_upgrade_handler" "upgradeState(bytes32)(uint8)" "$PROPOSAL_ID")
fi

echo "Proposal ID: $PROPOSAL_ID"
if [[ -n "$RPC_URL" ]]; then
	echo "Upgrade state in the ProtocolUpgradeHandler $protocol_upgrade_handler: ${UPGRADE_STATES[$upgrade_state]} (only a Waiting upgrade can be approved)"
fi
echo "Security Council: $SECURITY_COUNCIL (chain ID $CHAIN_ID)"
echo "Member Safe: $MEMBER_SAFE"
echo "Safe message: $safe_msg"
echo "Safe message hash: $safe_msg_hash"
echo "Domain hash: $(format_hash "$safe_domain_hash")"
echo "Message hash: $(format_hash "$message_hash")"
