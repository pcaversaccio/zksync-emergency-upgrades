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
# - `0x303a465b659cbb0ab36ee643ea362c509eeb5213` = ZK bridge hub contract
#   - `0xac700e63` = `bytes4(keccak256("pauseMigration()"))`
# - `0xeb998f917e759449046361bc278f63fb6e576f80` = Governance upgrade timer contract
# 	- `0xa39f7449` = `bytes4(keccak256("startTimer()"))`
readonly CALLS="[(0x303a465b659cbb0ab36ee643ea362c509eeb5213,0,0xac700e63),\
				 (0xeb998f917e759449046361bc278f63fb6e576f80,0,0xa39f7449)]"

# Define the executor contract.
readonly EXECUTOR="0xF73a7dCfa68E52030ec39E41a23DCA51F3aAa111"

# Salt value as a hex string.
readonly SALT="0x0000000000000000000000000000000000000000000000000000000000000001"

# Encode the `UpgradeProposal` struct.
encoded_proposal=$(cast abi-encode "UpgradeProposal(((address,uint256,bytes)[],address,bytes32))" "($CALLS,$EXECUTOR,$SALT)")

# Compute the `keccak256` hash of the encoded proposal.
proposal_id=$(cast keccak "$encoded_proposal")

# Save the proposal ID to a file.
echo "$proposal_id" >proposal_id_stage0.txt

# Output the result.
echo "Encoded \`UpgradeProposal\` struct (stage 0): $encoded_proposal"
echo "Proposal ID: $proposal_id"
