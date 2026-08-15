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
# - `0x93eb31af637d8bf6cfa0a69291e4f7f9edf09ee5` = Upgrade stage validator contract
#   - `0x37076ce3` = `bytes4(keccak256("checkProtocolUpgradePresence()"))`
# - `0x303a465b659cbb0ab36ee643ea362c509eeb5213` = ZK bridge hub contract
#   - `0xf7c7eb92` = `bytes4(keccak256("unpauseMigration()"))`
# - `0x93eb31af637d8bf6cfa0a69291e4f7f9edf09ee5` = Upgrade stage validator contract
#   - `0x407a5a0b` = `bytes4(keccak256("checkMigrationsUnpaused()"))`
readonly CALLS="[(0x93eb31af637d8bf6cfa0a69291e4f7f9edf09ee5,0,0x37076ce3),\
				 (0x303a465b659cbb0ab36ee643ea362c509eeb5213,0,0xf7c7eb92),\
				 (0x93eb31af637d8bf6cfa0a69291e4f7f9edf09ee5,0,0x407a5a0b)]"

# Define the executor contract.
readonly EXECUTOR="0xF73a7dCfa68E52030ec39E41a23DCA51F3aAa111"

# Salt value as a hex string.
readonly SALT="0x0000000000000000000000000000000000000000000000000000000000000000"

# Encode the `UpgradeProposal` struct.
encoded_proposal=$(cast abi-encode "UpgradeProposal(((address,uint256,bytes)[],address,bytes32))" "($CALLS,$EXECUTOR,$SALT)")

# Compute the `keccak256` hash of the encoded proposal.
proposal_id=$(cast keccak "$encoded_proposal")

# Save the proposal ID to a file.
echo "$proposal_id" >proposal_id_stage2.txt

# Output the result.
echo "Encoded \`UpgradeProposal\` struct (stage 2): $encoded_proposal"
echo "Proposal ID: $proposal_id"
