#!/usr/bin/env bash

# Define the parameters for the `UpgradeProposal` struct.
readonly CALLS="[(0x303a465b659cbb0ab36ee643ea362c509eeb5213,0,0x79ba5097),(0xc2ee6b6af7d616f6e27ce7f4a451aedc2b0f5f5c,0,0x79ba5097),(0xd7f9f54194c633f36ccd5f3da84ad4a1c38cb2cb,0,0x79ba5097),(0x5d8ba173dc6c3c90c8f7c04c9288bef5fdbad06e,0,0x79ba5097),(0xf553e6d903aa43420ed7e3bc2313be9286a8f987,0,0x79ba5097)]"

# Define the executor contract.
readonly EXECUTOR="0xECE8e30bFc92c2A8e11e6cb2e17B70868572E3f6"

# Salt value as a hex string.
readonly SALT="0x0000000000000000000000000000000000000000000000000000000000000000"

# Encode the `UpgradeProposal` struct.
encoded_proposal=$(cast abi-encode "UpgradeProposal(((address,uint256,bytes)[],address,bytes32))" "($CALLS,$EXECUTOR,$SALT)")

# Compute the `keccak256` hash of the encoded proposal.
proposal_id=$(cast keccak "$encoded_proposal")

# Save the proposal ID to a file.
echo "$proposal_id" > proposal_id.txt

# Output the result.
echo "Encoded \`UpgradeProposal\` struct: $encoded_proposal"
echo "Proposal ID: $proposal_id"
