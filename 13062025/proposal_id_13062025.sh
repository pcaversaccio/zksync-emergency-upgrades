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

# Define the parameters for the `Proposal`.
# The proposal transaction has been sent here: https://era.zksync.network/tx/0x4a6ae10ac98fb20dad6b4ba912de9ba8d723be24661a090c931feef47b72bd6e.
readonly TARGETS="[0x9c263585e7cea3a89e61c491dc02ff283906fbf0]"
readonly VALUES="[0]"
readonly CALLDATAS="[0x]"
readonly DESCRIPTION=$(
	cat <<'EOF'
# [TEST-TPP] Guardian Veto Rehearsal 2025-Q2
# \[TEST-TPP] Guardian Veto Rehearsal 2025-Q2

**Token Program Proposal Summary**

| Item                 | Description                                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| Title                | Guardian Veto Rehearsal 2025-Q2                                                                         |
| Proposal Type        | TPP                                                                                                     |
| One Sentence Summary | This proposal forms part of a Guardian veto rehearsal to test a production Token Program Proposal veto. |
| Proposal Author      | ZKsync Association                                                                                      |
| Proposal Sponsor     | Keating, ScopeLift                                                                                      |
| Date Created         | 2025-JUNE-02                                                                                            |
| Version              | 1.0                                                                                                     |
| Summary of Action    | This proposal has no onchain actions                                                                    |
| Link to Forum        | https://forum.zknation.io/t/tpp-t1-guardian-veto-rehearsal-1-2025/695                                   |
| Link to Contracts    | Not Applicable                                                                                          |

***

### :::: NO VOTE FROM DELEGATES REQUIRED ::::&#xA;&#xA;

### Summary

This proposal coordinates a production onchain veto rehearsal for Guardians on the ZKsync Era Token Governor. It simulates a real-world scenario in which a Guardian veto is required, ensuring veto functionality, multisig coordination, and interfaces perform as expected.

***

### Abstract

Guardian powers have been live since the launch of ZKsync governance in September 2024. As of today, no proposals have yet required a formal veto. To ensure operational readiness, the Governance Team is organizing regular rehearsals. This rehearsal will test the Guardian veto path on a **Token Program Proposal (TPP)**.

The rehearsal follows the complete process: proposal submission, veto initiation, multisig signature collection, execution, and validation via the Tally interface.

This exercise helps ensure ZKsync’s governance infrastructure is functional, transparent, and trustworthy in moments of real escalation.

***

### Impact

This rehearsal will validate the following:

* Guardian veto functionality on the Token Governor contract
* Signature gathering and quorum on the Guardian multisig
* Execution reliability through the [verify.zknation.io](https://verify.zknation.io/) interface
* Proper UI state change on Tally and governance dashboards

It also reinforces cross-role coordination between proposers, Guardians, and interfaces.

No ZK tokens will be minted, burned, or reallocated during this process. This is a simulation only.

***

### Plan

* **June 2, 2025 – 15:00 CET**: Draft proposal posted on ZKsync Governance Forum
* **June 9, 2025 – 15:00 CET**: Test proposal submitted on ZKsync Governance Portal
* **June 20, 2025 – 18:00 CET**: Guardian veto execution deadline
EOF
)

# Encode the `Proposal`. See the `ZkTokenGovernor` contract here: https://era.zksync.network/address/0xb83FF6501214ddF40C91C9565d095400f3F45746:
# ```solidity
# function propose(
# 	address[] memory targets,
# 	uint256[] memory values,
# 	bytes[] memory calldatas,
# 	string memory description
# ) public virtual override returns (uint256) {
#   ...
# 	uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
#   ...
#
# function hashProposal(
# 	address[] memory targets,
# 	uint256[] memory values,
# 	bytes[] memory calldatas,
# 	bytes32 descriptionHash
# ) public pure virtual override returns (uint256) {
# 	return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
# }
#```
description_utf8_bytes=$(printf %s "$DESCRIPTION" | cast from-utf8)
description_hash=$(cast keccak "$description_utf8_bytes")
encoded_proposal=$(cast abi-encode "Proposal(address[],uint256[],bytes[],bytes32)" "$TARGETS" "$VALUES" "$CALLDATAS" "$description_hash")

# Compute the `keccak256` hash of the encoded proposal and convert it to a decimal number.
proposal_id=$(cast keccak "$encoded_proposal" | cast to-dec)

# Save the proposal ID to a file.
echo "$proposal_id" >proposal_id.txt

# Output the result.
echo "Encoded \`Proposal\`: $encoded_proposal"
echo "Proposal ID: $proposal_id"
