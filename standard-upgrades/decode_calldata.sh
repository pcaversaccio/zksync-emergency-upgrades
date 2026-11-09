#!/usr/bin/env bash

########################
# Don't trust, verify! #
########################

# @license GNU Affero General Public License v3.0 only
# @author pcaversaccio
# @author Stanislav Bezkorovainyi

# Decodes calldata into the function, its named arguments and, recursively, every `bytes`
# argument that is itself a known call. For the `Governance` calls `scheduleTransparent`,
# `execute` and `executeInstant`, it also prints the operation ID, so a `scheduleTransparent`
# and its `execute` can be matched.
#
# Signatures and argument names come from `known_functions.jsonl` next to this script: one
# function per line, taken from the ABIs of the ZKsync contracts. A selector that isn't
# listed is looked up with `cast 4byte-decode` (a public signature database) and flagged.
#
# Usage:
#   ./decode_calldata.sh <calldata> [indent]
#
# `indent` is the number of spaces every line starts with (default 0).

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

readonly KNOWN_FUNCTIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/known_functions.jsonl"
readonly MAX_UINT256="115792089237316195423570985008687907853269984665640564039457584007913129639935"
# `bytes` arguments are decoded as calls up to this depth.
readonly MAX_DEPTH=8
# The `Governance` functions whose argument is an `Operation`.
# => `bytes4(keccak256("scheduleTransparent(((address,uint256,bytes)[],bytes32,bytes32),uint256)"));`
readonly SCHEDULE_TRANSPARENT_SELECTOR="0x2c431917"
# => `bytes4(keccak256("execute(((address,uint256,bytes)[],bytes32,bytes32))"));`
readonly EXECUTE_SELECTOR="0x74da756b"
# => `bytes4(keccak256("executeInstant(((address,uint256,bytes)[],bytes32,bytes32))"));`
readonly EXECUTE_INSTANT_SELECTOR="0x95218ecd"

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	sed -n '/^# Usage:/,/^# `indent`/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 1
}

lowercase() {
	echo "$1" | tr '[:upper:]' '[:lower:]'
}

pad() {
	printf '%*s' "$1" ""
}

# Formats a packed protocol version (`major << 64 | minor << 32 | patch`) as `vX.Y.Z`.
semver() {
	local hex
	hex=$(cast to-hex "$1" </dev/null)
	hex=$(printf '%064s' "${hex:2}" | tr ' ' 0)
	echo "v$((16#${hex:32:16})).$((16#${hex:48:8})).$((16#${hex:56:8}))"
}

# Prints the `Governance` operation ID, `keccak256(abi.encode(_operation))`. The `Operation`
# is the only dynamic argument, so `abi.encode(_operation)` is the offset word `0x20`
# followed by the calldata from the offset in the first argument word on.
print_operation_id() {
	local data=$1 indent=$2 offset
	offset=$((16#${data:10:64}))
	echo "$(pad "$indent")Governance operation ID: $(cast keccak "0x$(printf '%064x' 32)${data:$((10 + offset * 2))}" </dev/null)"
}

# Turns the decoded values into lines `kind<TAB>depth<TAB>label<TAB>value`, walking the
# function's inputs (`jq` input: `{inputs, values}`). The kinds: `H` is a tuple or array
# header, `B` is `bytes`, `V` is an unsigned integer that every name calls a protocol version,
# `S` is anything else. All numbers arrive as strings, so `jq` never rounds them.
readonly RENDER='
def arglabel($p; $i): (if ($p.name // "") == "" then "arg\($i)" else $p.name end) + " (" + $p.type + ")";
def is_version($p):
	($p.name // "") != "" and
	(($p.name | split(" | ")) | all(test("protocolversion"; "i") and (test("deadline"; "i") | not)));
def render($p; $v; $depth; $lbl):
	if ($p.type | endswith("]")) then
		[$depth, "H", $lbl, ""],
		(($p | .type |= sub("\\[[0-9]*\\]$"; "")) as $element
			| range(0; $v | length) as $j
			| render($element; $v[$j]; $depth + 1; "[\($j)] (\($element.type))"))
	elif $p.type == "tuple" then
		[$depth, "H", $lbl, ""],
		(range(0; $p.components | length) as $j
			| render($p.components[$j]; $v[$j]; $depth + 1; arglabel($p.components[$j]; $j)))
	elif $p.type == "bytes" then [$depth, "B", $lbl, $v]
	elif ($p.type | startswith("uint")) and is_version($p) then [$depth, "V", $lbl, $v]
	elif ($p.type | startswith("uint")) or ($p.type | startswith("int")) or $p.type == "address"
		or $p.type == "bool" or ($p.type | startswith("bytes")) then [$depth, "S", $lbl, ($v | tostring)]
	else [$depth, "S", $lbl, ($v | tojson)]
	end;
range(0; .inputs | length) as $i | render(.inputs[$i]; .values[$i]; 0; arglabel(.inputs[$i]; $i)) | map(tostring) | join("\t")
'

# Prints the decoded call with every line indented by `indent` spaces. Without printing
# anything, returns 1 if the selector is not a known function, and 2 if it is but the
# calldata does not decode as its arguments.
decode_known() {
	local data=$1 indent=$2 depth=$3 selector entry signature values lines
	selector=$(lowercase "${data:0:10}")
	entry=$(grep -F "\"selector\":\"$selector\"" "$KNOWN_FUNCTIONS" | head -n 1) || return 1
	signature=$(echo "$entry" | jq -r .signature)
	if [[ "$signature" == *"()" ]]; then
		# `cast` refuses to decode no arguments, so check that nothing follows the selector.
		[[ ${#data} == 10 ]] || return 2
		values="[]"
	else
		# `cast` prints one scalar per line. Quoting the bare numbers keeps `jq` from rounding them.
		values=$(cast calldata-decode --json "$signature" "$data" </dev/null 2>/dev/null) || return 2
	fi
	values=$(echo "$values" | sed -E 's/^([[:space:]]*)(-?[0-9]+)(,?)$/\1"\2"\3/')
	lines=$(jq -rn --argjson entry "$entry" --argjson values "$values" \
		"{inputs: \$entry.inputs, values: \$values} | $RENDER") || return 2

	echo "$(pad "$indent")function: $signature"
	local line_depth kind lbl value prefix
	while IFS=$'\t' read -r line_depth kind lbl value; do
		[[ -n "$kind" ]] || continue
		prefix="$(pad $((indent + 2 + line_depth * 2)))$lbl"
		case "$kind" in
		H) echo "$prefix:" ;;
		V) echo "$prefix: $value ($(semver "$value"))" ;;
		B)
			echo "$prefix: $value"
			if [[ ${#value} -ge 10 && $depth -lt $MAX_DEPTH ]]; then
				decode_known "$value" $((indent + 4 + line_depth * 2)) $((depth + 1)) || true
			fi
			;;
		*)
			if [[ "$value" == "$MAX_UINT256" ]]; then
				echo "$prefix: $value (type(uint256).max)"
			else
				echo "$prefix: $value"
			fi
			;;
		esac
	done <<<"$lines"

	case "$selector" in
	"$SCHEDULE_TRANSPARENT_SELECTOR" | "$EXECUTE_SELECTOR" | "$EXECUTE_INSTANT_SELECTOR")
		print_operation_id "$data" "$((indent + 2))"
		;;
	esac
}

decode() {
	local data=$1 indent=$2 decoded status=0
	if [[ ${#data} -lt 10 ]]; then
		echo "$(pad "$indent")(no calldata)"
		return
	fi
	decode_known "$data" "$indent" 0 || status=$?
	if [[ $status == 0 ]]; then
		:
	elif [[ $status == 2 ]]; then
		echo "$(pad "$indent")WARNING: ${data:0:10} is a known function, but the calldata does not decode as its arguments"
	elif decoded=$(cast 4byte-decode "$data" </dev/null 2>/dev/null) && [[ -n "$decoded" ]]; then
		echo "$(pad "$indent")WARNING: ${data:0:10} is not a known function. The signature below comes from a public"
		echo "$(pad "$indent")database, and the argument names are unknown:"
		echo "$decoded" | sed "s/^/$(pad $((indent + 2)))/"
	else
		echo "$(pad "$indent")WARNING: unknown selector ${data:0:10}, the calldata is not decoded"
	fi
}

[[ $# -ge 1 && $# -le 2 ]] || usage
command -v jq >/dev/null || die "jq is required"
DATA=$1
INDENT=${2:-0}
[[ "$DATA" =~ ^0x([0-9a-fA-F]{2})*$ ]] || die "the calldata must be 0x-prefixed hex, got '$DATA'"
[[ "$INDENT" =~ ^[0-9]+$ ]] || die "the indent must be a number, got '$INDENT'"
decode "$DATA" "$INDENT"
