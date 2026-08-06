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

# Define the parameters for the `UpgradeProposal` struct.
# The calldata decodes to (always verify this yourself!):
# - `0x2e5110cf18678ec99818bfaa849b8c881744b776` = `ValidatorTimelock` contract
#   (owned by the `ProtocolUpgradeHandler` and the currently registered validator of ZKsync Era)
# 	- `0xf34d1868` = `bytes4(keccak256("setExecutionDelay(uint32)"))`
# 	- `_executionDelay` = `0x3f480` = `259200` seconds = 72 hours (the current value is `10800` seconds = 3 hours)
readonly CALLS="[(0x2e5110cf18678ec99818bfaa849b8c881744b776,0,0xf34d1868000000000000000000000000000000000000000000000000000000000003f480)]"

# Define the executor contract.
readonly EXECUTOR="0xF73a7dCfa68E52030ec39E41a23DCA51F3aAa111"

# Salt value as a hex string.
readonly SALT="0x0000000000000000000000000000000000000000000000000000000000000000"

# Encode the `UpgradeProposal` struct.
encoded_proposal=$(cast abi-encode "UpgradeProposal(((address,uint256,bytes)[],address,bytes32))" "($CALLS,$EXECUTOR,$SALT)")

# Compute the `keccak256` hash of the encoded proposal.
proposal_id=$(cast keccak "$encoded_proposal")

# Save the proposal ID to a file.
echo "$proposal_id" >proposal_id.txt

# Output the result.
echo "Encoded \`UpgradeProposal\` struct: $encoded_proposal"
echo "Proposal ID: $proposal_id"
