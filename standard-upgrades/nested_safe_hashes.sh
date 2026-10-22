#!/usr/bin/env bash

########################
# Don't trust, verify! #
########################

# @license GNU Affero General Public License v3.0 only

# Shows what a member Safe has to sign to approve a transaction of a parent Safe whose
# owners are themselves Safes. The main use case is the Security Council Safe that owns
# the ZKsync OS ecosystem `Governance`: its owners are the Security Council member Safes,
# so every standard (`Governance`-based) upgrade is a transaction of the Security Council
# Safe that the member Safes approve.
#
# A member Safe approves the parent's `safeTxHash` in one of two ways, picked with exactly
# one of these flags:
#   --onchain-tx    The member Safe executes `parent.approveHash(safeTxHash)`. Its owners
#                   sign a regular Safe transaction of the member Safe. This is what
#                   Safe{Wallet} proposes when a nested Safe confirms a transaction.
#   --offchain-sig  The member Safe's owners sign a `SafeMessage` (EIP-1271) whose `message`
#                   is the parent's EIP-712 preimage (`0x1901 || domain hash || message hash`).
#                   The parent (Safe >= 1.3.0) calls the member's legacy
#                   `isValidSignature(bytes,bytes)` with exactly that preimage.
#
# The parent transaction comes from a Safe{Wallet} link (`--safe-link`), which is fetched
# from the Safe Transaction Service, or from flags (`--to`, `--data`, ...). The script
# recomputes the `safeTxHash` locally and stops if it differs from the one in the link, so
# the Safe Transaction Service does not have to be trusted. It prints the calls being
# approved, then the hashes to sign. With `--rpc-url`, the nonces default to the current
# on-chain ones, and every hash is cross-checked against the Safe contracts.
#
# Usage:
#   ./nested_safe_hashes.sh (--onchain-tx | --offchain-sig) --member-safe <address> \
#       (--safe-link <url> | --to <address> --data <hex> [--value <wei>] [--operation <0|1>] \
#           [--parent-safe <address>] [--nonce <parent nonce>] [--chain-id <id>]) \
#       [--member-nonce <member nonce>] [--rpc-url <url>]
#
# Without `--safe-link`, `--parent-safe` defaults to the mainnet Security Council Safe,
# `--value` and `--operation` to 0, `--chain-id` to 1, and `safeTxGas`, `baseGas`,
# `gasPrice`, `gasToken` and `refundReceiver` are 0, which is what Safe{Wallet} uses.
# Without `--rpc-url`, `--member-nonce` is required for `--onchain-tx`, and so is `--nonce`
# without `--safe-link`.

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

lowercase() {
	echo "$1" | tr '[:upper:]' '[:lower:]'
}

usage() {
	sed -n '/^# Usage:/,/^# without `--safe-link`/p' "$0" | sed 's/^# \{0,1\}//' >&2
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
# => `keccak256("SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)");`
# See: https://github.com/safe-fndn/safe-smart-account/blob/a0a1d4292006e26c4dbd52282f4c932e1ffca40f/contracts/Safe.sol#L59-L62.
readonly SAFE_TX_TYPEHASH="0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8"
# => `keccak256("SafeMessage(bytes message)");`
# See: https://github.com/safe-fndn/safe-smart-account/blob/febab5e4e859e6e65914f17efddee415e4992961/contracts/libraries/SignMessageLib.sol#L12-L13.
readonly SAFE_MSG_TYPEHASH="0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca"
# => `bytes4(keccak256("approveHash(bytes32)"))`
readonly APPROVE_HASH_SELECTOR="0xd4d9bdcd"
# => `bytes4(keccak256("multiSend(bytes)"))`
readonly MULTI_SEND_SELECTOR="0x8d80ff0a"
readonly ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

# The canonical `MultiSend` and `MultiSendCallOnly` deployments (v1.3.0 and v1.4.1), the only
# delegatecall targets that are expected.
readonly MULTI_SEND_ADDRESSES="0xa238cbeb142c10ef7ad8442c6d1f9e89e07e7761 0x40a2accbd92bca938b02010e17a5b8929b49130d 0x38869bf66a61cf6bdb996a6ae40d5853fd43b526 0x9641d764fc13c8b624c04430c7356c1c7c8102e2"

# The mainnet Security Council Safe, owned by the Security Council member Safes.
PARENT_SAFE="0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63"
MODE="" MEMBER_SAFE="" SAFE_LINK="" TO="" DATA="" VALUE="0" OPERATION="0" NONCE="" MEMBER_NONCE="" CHAIN_ID="1" RPC_URL=""
SAFE_TX_GAS="0" BASE_GAS="0" GAS_PRICE="0" GAS_TOKEN="$ZERO_ADDRESS" REFUND_RECEIVER="$ZERO_ADDRESS"

set_mode() {
	[[ -z "$MODE" || "$MODE" == "$1" ]] || die "pass only one of --onchain-tx and --offchain-sig"
	MODE="$1"
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	--onchain-tx) set_mode onchain; shift ;;
	--offchain-sig) set_mode offchain; shift ;;
	--member-safe) MEMBER_SAFE="$2"; shift 2 ;;
	--safe-link) SAFE_LINK="$2"; shift 2 ;;
	--parent-safe) PARENT_SAFE="$2"; shift 2 ;;
	--to) TO="$2"; shift 2 ;;
	--data) DATA="$2"; shift 2 ;;
	--value) VALUE="$2"; shift 2 ;;
	--operation) OPERATION="$2"; shift 2 ;;
	--nonce) NONCE="$2"; shift 2 ;;
	--member-nonce) MEMBER_NONCE="$2"; shift 2 ;;
	--chain-id) CHAIN_ID="$2"; shift 2 ;;
	--rpc-url) RPC_URL="$2"; shift 2 ;;
	-h | --help) usage ;;
	*) die "unknown argument $1" ;;
	esac
done
[[ -n "$MODE" ]] || { echo "Error: pass one of --onchain-tx and --offchain-sig" >&2; usage; }
[[ -n "$MEMBER_SAFE" ]] || usage
if [[ -n "$SAFE_LINK" ]]; then
	[[ -z "$TO$DATA$NONCE" ]] || die "pass either --safe-link or --to/--data/--nonce, not both"
else
	[[ -n "$TO" && -n "$DATA" ]] || usage
fi
[[ "$MODE" == "onchain" || -z "$MEMBER_NONCE" ]] || die "--member-nonce only applies to --onchain-tx"

call() {
	cast call "$@" --rpc-url "$RPC_URL"
}

# Fails if the hash computed locally differs from the expected one.
check_eq() {
	local what=$1 computed=$2 expected=$3
	[[ "$(lowercase "$computed")" == "$(lowercase "$expected")" ]] ||
		die "$what mismatch: computed $computed, expected $expected"
}

safe_domain_hash() {
	cast keccak "$(cast abi-encode "f(bytes32,uint256,address)" "$SAFE_DOMAIN_SEPARATOR_TYPEHASH" "$CHAIN_ID" "$1")"
}

safe_tx_struct_hash() {
	local to=$1 value=$2 data=$3 operation=$4 safe_tx_gas=$5 base_gas=$6 gas_price=$7 gas_token=$8 refund_receiver=$9 nonce=${10}
	cast keccak "$(cast abi-encode "f(bytes32,address,uint256,bytes32,uint8,uint256,uint256,uint256,address,address,uint256)" \
		"$SAFE_TX_TYPEHASH" "$to" "$value" "$(cast keccak "$data")" "$operation" "$safe_tx_gas" "$base_gas" "$gas_price" "$gas_token" "$refund_receiver" "$nonce")"
}

safe_get_transaction_hash() {
	local safe=$1
	shift
	call "$safe" "getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)" "$@"
}

# Prints one call: its target, value, calldata and the calldata decoded via `cast 4byte-decode`.
# The function signature comes from a public signature database, the arguments are decoded locally.
print_call() {
	local index=$1 to=$2 value=$3 data=$4
	echo "Call $index:"
	echo "  to: $(cast to-check-sum-address "$to")"
	echo "  value: $value wei"
	echo "  data: $data"
	if [[ ${#data} -lt 10 ]]; then
		echo "  decoded: (no calldata)"
	elif decoded=$(cast 4byte-decode "$data" 2>/dev/null) && [[ -n "$decoded" ]]; then
		echo "  decoded:"
		echo "$decoded" | sed 's/^/    /'
	else
		echo "  decoded: unknown selector ${data:0:10}"
	fi
}

# Prints the calls of the parent transaction, splitting a `multiSend` batch into its calls.
# A `multiSend` packs each call as `operation (1 byte) || to (20 bytes) || value (32 bytes) ||
# data length (32 bytes) || data`.
print_calls() {
	if [[ "$OPERATION" == "1" && "$(lowercase "${DATA:0:10}")" == "$MULTI_SEND_SELECTOR" ]]; then
		[[ " $MULTI_SEND_ADDRESSES " == *" $(lowercase "$TO") "* ]] ||
			echo "WARNING: the batch is a delegatecall to $TO, which is not a canonical MultiSend contract"
		local packed offset=0 index=1 call_operation call_to call_value data_length call_data
		packed=$(cast calldata-decode "multiSend(bytes)" "$DATA")
		packed=${packed:2}
		echo "MultiSend batch via $TO:"
		while [[ $offset -lt ${#packed} ]]; do
			call_operation=$((16#${packed:$offset:2}))
			call_to="0x${packed:$((offset + 2)):40}"
			call_value=$(cast to-dec "0x${packed:$((offset + 42)):64}")
			data_length=$((16#${packed:$((offset + 106)):64}))
			call_data="0x${packed:$((offset + 170)):$((data_length * 2))}"
			[[ $call_operation == 0 ]] || echo "WARNING: call $index is a delegatecall"
			print_call "$index" "$call_to" "$call_value" "$call_data"
			offset=$((offset + 170 + data_length * 2))
			index=$((index + 1))
		done
	else
		[[ "$OPERATION" == "0" ]] || echo "WARNING: the transaction is a delegatecall to $TO"
		print_call 1 "$TO" "$VALUE" "$DATA"
	fi
}

# Load the parent transaction from the Safe{Wallet} link, e.g.
# `https://app.safe.global/transactions/tx?safe=eth:0x...&id=multisig_0x<safe>_0x<safeTxHash>`.
LINK_SAFE_TX_HASH=""
if [[ -n "$SAFE_LINK" ]]; then
	command -v jq >/dev/null || die "jq is required for --safe-link"
	[[ "$SAFE_LINK" =~ safe=([a-z0-9-]+):(0x[0-9a-fA-F]{40}) ]] || die "the link has no safe=<chain>:<address>"
	chain_prefix=${BASH_REMATCH[1]}
	PARENT_SAFE=${BASH_REMATCH[2]}
	[[ "$SAFE_LINK" =~ multisig_0x[0-9a-fA-F]{40}_(0x[0-9a-fA-F]{64}) ]] || die "the link has no id=multisig_<safe>_<safeTxHash>"
	LINK_SAFE_TX_HASH=${BASH_REMATCH[1]}
	case "$chain_prefix" in
	eth) CHAIN_ID="1"; api="https://safe-transaction-mainnet.safe.global" ;;
	sep) CHAIN_ID="11155111"; api="https://safe-transaction-sepolia.safe.global" ;;
	*) die "unsupported chain prefix $chain_prefix in the link (supported: eth, sep)" ;;
	esac
	tx=$(curl -fsSL "$api/api/v2/multisig-transactions/$LINK_SAFE_TX_HASH/") ||
		die "the Safe Transaction Service has no transaction $LINK_SAFE_TX_HASH"
	[[ "$(lowercase "$(echo "$tx" | jq -r .safe)")" == "$(lowercase "$PARENT_SAFE")" ]] ||
		die "the Safe Transaction Service returned a transaction of another Safe"
	TO=$(echo "$tx" | jq -r .to)
	VALUE=$(echo "$tx" | jq -r .value)
	DATA=$(echo "$tx" | jq -r '.data // "0x"')
	OPERATION=$(echo "$tx" | jq -r .operation)
	SAFE_TX_GAS=$(echo "$tx" | jq -r .safeTxGas)
	BASE_GAS=$(echo "$tx" | jq -r .baseGas)
	GAS_PRICE=$(echo "$tx" | jq -r .gasPrice)
	GAS_TOKEN=$(echo "$tx" | jq -r .gasToken)
	REFUND_RECEIVER=$(echo "$tx" | jq -r .refundReceiver)
	NONCE=$(echo "$tx" | jq -r .nonce)
fi
[[ "$OPERATION" == "0" || "$OPERATION" == "1" ]] || die "the operation must be 0 (call) or 1 (delegatecall)"

PARENT_SAFE=$(cast to-check-sum-address "$PARENT_SAFE")
MEMBER_SAFE=$(cast to-check-sum-address "$MEMBER_SAFE")
TO=$(cast to-check-sum-address "$TO")

if [[ -n "$RPC_URL" ]]; then
	[[ "$(cast chain-id --rpc-url "$RPC_URL")" == "$CHAIN_ID" ]] || die "the RPC is not for chain $CHAIN_ID"
	[[ "$(call "$PARENT_SAFE" "isOwner(address)(bool)" "$MEMBER_SAFE")" == "true" ]] ||
		die "$MEMBER_SAFE is not an owner of $PARENT_SAFE"
	[[ -n "$NONCE" ]] || NONCE=$(call "$PARENT_SAFE" "nonce()(uint256)")
	if [[ "$MODE" == "onchain" && -z "$MEMBER_NONCE" ]]; then
		MEMBER_NONCE=$(call "$MEMBER_SAFE" "nonce()(uint256)")
	fi
fi
[[ -n "$NONCE" ]] || die "pass --nonce (the parent Safe's nonce of the transaction), --safe-link or --rpc-url"
[[ "$MODE" == "offchain" || -n "$MEMBER_NONCE" ]] || die "pass --member-nonce (the member Safe's next nonce) or --rpc-url"

# The parent Safe transaction.
PARENT_TX=("$TO" "$VALUE" "$DATA" "$OPERATION" "$SAFE_TX_GAS" "$BASE_GAS" "$GAS_PRICE" "$GAS_TOKEN" "$REFUND_RECEIVER" "$NONCE")
parent_domain_hash=$(safe_domain_hash "$PARENT_SAFE")
parent_message_hash=$(safe_tx_struct_hash "${PARENT_TX[@]}")
# The EIP-712 preimage of the parent's `safeTxHash`.
parent_preimage=$(cast concat-hex 0x1901 "$parent_domain_hash" "$parent_message_hash")
parent_safe_tx_hash=$(cast keccak "$parent_preimage")
member_domain_hash=$(safe_domain_hash "$MEMBER_SAFE")

if [[ -n "$LINK_SAFE_TX_HASH" ]]; then
	check_eq "safeTxHash of the link" "$parent_safe_tx_hash" "$LINK_SAFE_TX_HASH"
fi
if [[ -n "$RPC_URL" ]]; then
	check_eq "parent safeTxHash" "$parent_safe_tx_hash" "$(safe_get_transaction_hash "$PARENT_SAFE" "${PARENT_TX[@]}")"
	check_eq "member domain hash" "$member_domain_hash" "$(call "$MEMBER_SAFE" "domainSeparator()(bytes32)")"
fi

if [[ "$MODE" == "onchain" ]]; then
	approve_data=$(cast concat-hex "$APPROVE_HASH_SELECTOR" "$parent_safe_tx_hash")
	member_message_hash=$(safe_tx_struct_hash "$PARENT_SAFE" 0 "$approve_data" 0 0 0 0 "$ZERO_ADDRESS" "$ZERO_ADDRESS" "$MEMBER_NONCE")
	member_safe_tx_hash=$(cast keccak "$(cast concat-hex 0x1901 "$member_domain_hash" "$member_message_hash")")
	if [[ -n "$RPC_URL" ]]; then
		check_eq "member safeTxHash" "$member_safe_tx_hash" "$(safe_get_transaction_hash "$MEMBER_SAFE" \
			"$PARENT_SAFE" 0 "$approve_data" 0 0 0 0 "$ZERO_ADDRESS" "$ZERO_ADDRESS" "$MEMBER_NONCE")"
	fi
else
	# `keccak256(message)` is the parent's `safeTxHash` itself.
	member_message_hash=$(cast keccak "$(cast abi-encode "f(bytes32,bytes32)" "$SAFE_MSG_TYPEHASH" "$parent_safe_tx_hash")")
	safe_msg_hash=$(cast keccak "$(cast concat-hex 0x1901 "$member_domain_hash" "$member_message_hash")")
	if [[ -n "$RPC_URL" ]]; then
		check_eq "member Safe message hash" "$safe_msg_hash" "$(call "$MEMBER_SAFE" "getMessageHash(bytes)(bytes32)" "$parent_preimage")"
	fi
fi

echo "=== Transactions being approved ==="
print_calls
echo ""

echo "=== Parent Safe transaction ==="
echo "Parent Safe: $PARENT_SAFE (chain ID $CHAIN_ID)"
echo "to: $TO"
echo "value: $VALUE"
echo "operation: $OPERATION ($([[ "$OPERATION" == "0" ]] && echo call || echo delegatecall))"
echo "safeTxGas / baseGas / gasPrice: $SAFE_TX_GAS / $BASE_GAS / $GAS_PRICE"
echo "gasToken / refundReceiver: $GAS_TOKEN / $REFUND_RECEIVER"
echo "nonce: $NONCE"
echo "Domain hash: $(format_hash "$parent_domain_hash")"
echo "Message hash: $(format_hash "$parent_message_hash")"
echo "safeTxHash: $parent_safe_tx_hash$([[ -n "$LINK_SAFE_TX_HASH" ]] && echo " (matches the link)")"
if [[ -n "$RPC_URL" ]]; then
	approved=$(call "$PARENT_SAFE" "approvedHashes(address,bytes32)(uint256)" "$MEMBER_SAFE" "$parent_safe_tx_hash")
	echo "Already approved on-chain by $MEMBER_SAFE: $([[ "$approved" == "0" ]] && echo no || echo yes)"
fi
echo ""

if [[ "$MODE" == "onchain" ]]; then
	echo "=== Approve on-chain: the member Safe calls \`approveHash\` on the parent Safe ==="
	echo "The member Safe sends its own transaction that calls \`approveHash(safeTxHash)\` on the parent Safe."
	echo "It is recorded on-chain and counts as the member's signature when the parent transaction is executed."
	echo "It costs gas and uses the member Safe's nonce, so the hashes change if the member Safe executes"
	echo "anything else first. This is what Safe{Wallet} proposes when a nested Safe confirms a transaction."
	echo "The owners of the member Safe sign this transaction of the member Safe:"
	echo "Member Safe: $MEMBER_SAFE"
	echo "to: $PARENT_SAFE"
	echo "value: 0"
	echo "data: $approve_data"
	echo "  (approveHash($parent_safe_tx_hash))"
	echo "operation: 0 (call)"
	echo "nonce: $MEMBER_NONCE"
	echo "Domain hash: $(format_hash "$member_domain_hash")"
	echo "Message hash: $(format_hash "$member_message_hash")"
	echo "safeTxHash: $member_safe_tx_hash"
else
	echo "=== Approve off-chain: an EIP-1271 signature of the member Safe ==="
	echo "Nothing is sent on-chain. The owners of the member Safe sign a \`SafeMessage\` (an off-chain message in"
	echo "Safe{Wallet}). The signatures are passed to the parent Safe's \`execTransaction\`, which checks them"
	echo "with the member Safe's \`isValidSignature\` (EIP-1271). It costs no gas and does not use the member"
	echo "Safe's nonce."
	echo "The owners of the member Safe sign this message of the member Safe:"
	echo "Member Safe: $MEMBER_SAFE"
	echo "Safe message: $parent_preimage"
	echo "  (0x1901 || parent domain hash || parent message hash; its keccak256 is the parent safeTxHash)"
	echo "Safe message hash: $safe_msg_hash"
	echo "Domain hash: $(format_hash "$member_domain_hash")"
	echo "Message hash: $(format_hash "$member_message_hash")"
fi
