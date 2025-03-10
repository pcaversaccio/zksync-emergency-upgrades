// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

contract ProposalIdGoLive {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    struct UpgradeProposal {
        Call[] calls;
        address executor;
        bytes32 salt;
    }

    function computeProposalId() external pure returns (bytes32) {
        Call[] memory calls = new Call[](4);
        calls[0] = Call({target: 0xD7f9f54194C633F36CCD5F3da84ad4a1c38cB2cB, value: 0, data: hex"79ba5097"});
        calls[1] = Call({target: 0x303a465B659cBB0ab36eE643eA362c509EEb5213, value: 0, data: hex"79ba5097"});
        calls[2] = Call({target: 0xc2eE6b6af7d616f6e27ce7F4A451Aedc2b0F5f5C, value: 0, data: hex"79ba5097"});
        calls[3] = Call({target: 0x5D8ba173Dc6C3c90C8f7C04C9288BeF5FDbAd06E, value: 0, data: hex"79ba5097"});

        address executor = 0xdEFd1eDEE3E8c5965216bd59C866f7f5307C9b29;
        bytes32 salt = hex"646563656e7472616c697a6174696f6e206973206e6f74206f7074696f6e616c";

        UpgradeProposal memory upgradeProposal = UpgradeProposal({calls: calls, executor: executor, salt: salt});

        return keccak256(abi.encode(upgradeProposal));
    }
}
