#!/usr/bin/env bash

# Define the parameters for the `UpgradeProposal` struct.
readonly CALLS="[(0xD7f9f54194C633F36CCD5F3da84ad4a1c38cB2cB,0,0x79ba5097),(0x303a465B659cBB0ab36eE643eA362c509EEb5213,0,0x79ba5097),(0xc2eE6b6af7d616f6e27ce7F4A451Aedc2b0F5f5C,0,0x79ba5097),(0x5D8ba173Dc6C3c90C8f7C04C9288BeF5FDbAd06E,0,0x79ba5097)]"

# Define the executor contract.
readonly EXECUTOR="0xdEFd1eDEE3E8c5965216bd59C866f7f5307C9b29"

# Salt value ("decentralization is not optional") as a hex string.
readonly SALT="0x646563656e7472616c697a6174696f6e206973206e6f74206f7074696f6e616c"

# Encode the `UpgradeProposal` struct.
encoded_proposal=$(cast abi-encode "UpgradeProposal(((address,uint256,bytes)[],address,bytes32))" "($CALLS,$EXECUTOR,$SALT)")

# Compute the `keccak256` hash of the encoded proposal.
proposal_id=$(cast keccak "$encoded_proposal")

# Save the proposal ID to a file.
echo "$proposal_id" > proposal_id.txt

# Output the result.
echo "Encoded \`UpgradeProposal\` struct: $encoded_proposal"
echo "Proposal ID: $proposal_id"
