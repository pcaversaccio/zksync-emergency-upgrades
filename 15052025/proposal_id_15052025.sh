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
# - function `executeUpgrade`:
# - _chainId (uint256) = 2741 (Abstract chain ID)
# - _diamondCut (tuple)
#   - facetCuts (tuple[]) = []
#   - initAddress (address) = 0xdA5b3C1744798c2bFd528b3C506e7C955ef562B0 (https://gist.github.com/StanislavBreadless/15ed81aa82ce4d3a4a68e99dbf9edfb2#file-forcebatchproofupgrade-sol, deployed here: https://etherscan.io/address/0xdA5b3C1744798c2bFd528b3C506e7C955ef562B0)
#   - initCalldata (bytes) = 0x72b70e3a00000000000000000000000000000000000000000000000000000000000040918160bbaec2f006dc09f2de51ecd8ec750a11d6128ed48310b3d59c243bc0df23
#     This calldata decodes to (always verify this yourself!):
#     - function `forceProveBatches`
#     - toBatch (bytes32) = 16529 (https://abscan.org/batch/16529)
#     - expectedCommitment (bytes32) = 0x8160bbaec2f006dc09f2de51ecd8ec750a11d6128ed48310b3d59c243bc0df23 (cast call 0x2EDc71E9991A962c7FE172212d1aA9E50480fBb9 "storedBatchHash(uint256)" 16529 --rpc-url https://eth.llamarpc.com)
readonly CALLS="[(0xc2eE6b6af7d616f6e27ce7F4A451Aedc2b0F5f5C,0,0xe34a329a0000000000000000000000000000000000000000000000000000000000000ab500000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000060000000000000000000000000da5b3c1744798c2bfd528b3c506e7c955ef562b000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004472b70e3a00000000000000000000000000000000000000000000000000000000000040918160bbaec2f006dc09f2de51ecd8ec750a11d6128ed48310b3d59c243bc0df2300000000000000000000000000000000000000000000000000000000)]"

# Define the executor contract.
readonly EXECUTOR="0xECE8e30bFc92c2A8e11e6cb2e17B70868572E3f6"

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
