# ZKsync Emergency Upgrade Verification Tools <!-- omit from toc -->

- [Proposal ID Calculation for ZKsync `executeEmergencyUpgrade`s](#proposal-id-calculation-for-zksync-executeemergencyupgrades)
  - [Usage](#usage)
    - [Example 1 – Go-Live Emergency Upgrade](#example-1--go-live-emergency-upgrade)
    - [Example 2 – Accept Ownership After ZIP5 Emergency Upgrade](#example-2--accept-ownership-after-zip5-emergency-upgrade)
- [EIP-712-Based Off-Chain Message Safe Hashes](#eip-712-based-off-chain-message-safe-hashes)
- [Standard Upgrade Verification Tools](#standard-upgrade-verification-tools)
  - [`Governance`-Based Upgrades: Nested Safe Hashes](#governance-based-upgrades-nested-safe-hashes)
  - [Security Council Approval of Protocol Upgrades](#security-council-approval-of-protocol-upgrades)
- [💸 Donation](#-donation)

## Proposal ID Calculation for ZKsync `executeEmergencyUpgrade`s

> [!NOTE]
> The original gist can be found [here](https://gist.github.com/pcaversaccio/0ef8fb8034594e012a4903dfa992369e).

The function `executeEmergencyUpgrade` will be invoked in the following contract:

- `ProtocolUpgradeHandler`: [`0x8f7a9912416e8AdC4D9c21FAe1415D3318A11897`](https://etherscan.io/address/0x8f7a9912416e8AdC4D9c21FAe1415D3318A11897#code)

```solidity
/// @dev Represents a call to be made during an upgrade.
/// @param target The address to which the call will be made.
/// @param value The amount of Ether (in wei) to be sent along with the call.
/// @param data The calldata to be executed on the `target` address.
struct Call {
    address target;
    uint256 value;
    bytes data;
}

/// @dev Defines the structure of an upgrade that is executed by Protocol Upgrade Handler.
/// @param executor The L1 address that is authorized to perform the upgrade execution (if address(0) then anyone).
/// @param calls An array of `Call` structs, each representing a call to be made during the upgrade execution.
/// @param salt A bytes32 value used for creating unique upgrade proposal hashes.
struct UpgradeProposal {
    Call[] calls;
    address executor;
    bytes32 salt;
}

/// @notice Executes an emergency upgrade proposal initiated by the emergency upgrade board.
/// @param _proposal The upgrade proposal details including proposed actions and the executor address.
function executeEmergencyUpgrade(UpgradeProposal calldata _proposal) external payable onlyEmergencyUpgradeBoard {
    bytes32 id = keccak256(abi.encode(_proposal));
    UpgradeState upgState = upgradeState(id);
    // 1. Checks
    require(upgState == UpgradeState.None, "Upgrade already exists");
    require(_proposal.executor == msg.sender, "msg.sender is not authorized to perform the upgrade");
    // 2. Effects
    upgradeStatus[id].executed = true;
    // Clear the freeze
    lastFreezeStatusInUpgradeCycle = FreezeStatus.None;
    protocolFrozenUntil = 0;
    _unfreeze();
    // 3. Interactions
    _execute(_proposal.calls);
    emit Unfreeze();
    emit EmergencyUpgradeExecuted(id);
}
```

In order the retrieve the proposal ID, we need to calculate:

```solidity
keccak256(abi.encode(_proposal));
```

### Usage

> [!NOTE]
> Ensure that [`forge`](https://github.com/foundry-rs/foundry/tree/master/crates/forge) and [`cast`](https://github.com/foundry-rs/foundry/tree/master/crates/cast) are installed locally. For installation instructions, refer to this [guide](https://www.getfoundry.sh/introduction/installation).

Adjust the `executor`, `salt`, and `calls` parameters either in [`ProposalIdGoLive.sol`](./ProposalIdGoLive.sol) or [`proposal_id_go_live.sh`](./proposal_id_go_live.sh) and invoke

```console
forge script ProposalIdGoLive.sol --target-contract ProposalIdGoLive --sig "computeProposalId()"
```

or

```console
./proposal_id_go_live.sh
```

#### Example 1 – Go-Live Emergency Upgrade

The proposal ID, given by the ZKsync Era UI is `0xdd9aadc3b6e3297fed40a2cf0a7e655ff5af02c9ce918ed0e86f538c1c53ce9d`. So we need to verify that one.

From the docs [here](https://hackmd.io/@alishaZK/BJ7-jEv2C#Transaction-20), we know:

```console
bytes32 salt = 0x646563656e7472616c697a6174696f6e206973206e6f74206f7074696f6e616c
```

The executor in our case is [`0xdEFd1eDEE3E8c5965216bd59C866f7f5307C9b29`](https://etherscan.io/address/0xdEFd1eDEE3E8c5965216bd59C866f7f5307C9b29), the `EmergencyUpgradeBoard` contract.

**Proposal ID Calculation**

```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.38;

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
```

Now invoke:

```console
forge script ProposalIdGoLive.sol --target-contract ProposalIdGoLive --sig "computeProposalId()"
```

which will output:

```console
== Return ==
0: bytes32 0xdd9aadc3b6e3297fed40a2cf0a7e655ff5af02c9ce918ed0e86f538c1c53ce9d
```

#### Example 2 – Accept Ownership After ZIP5 Emergency Upgrade

The upgrade data for the emergency upgrade "Accept ownership after ZIP5":

```json
{
  "executor": "0xECE8e30bFc92c2A8e11e6cb2e17B70868572E3f6",
  "salt": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "calls": [
    {
      "target": "0x303a465b659cbb0ab36ee643ea362c509eeb5213",
      "value": "0x00",
      "data": "0x79ba5097"
    },
    {
      "target": "0xc2ee6b6af7d616f6e27ce7f4a451aedc2b0f5f5c",
      "value": "0x00",
      "data": "0x79ba5097"
    },
    {
      "target": "0xd7f9f54194c633f36ccd5f3da84ad4a1c38cb2cb",
      "value": "0x00",
      "data": "0x79ba5097"
    },
    {
      "target": "0x5d8ba173dc6c3c90c8f7c04c9288bef5fdbad06e",
      "value": "0x00",
      "data": "0x79ba5097"
    },
    {
      "target": "0xf553e6d903aa43420ed7e3bc2313be9286a8f987",
      "value": "0x00",
      "data": "0x79ba5097"
    }
  ]
}
```

**Proposal ID Calculation**

Run the script via:

```console
./proposal_id_zip5.sh
```

which returns

```console
Encoded `UpgradeProposal` struct: 0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ece8e30bfc92c2a8e11e6cb2e17b70868572e3f60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000320000000000000000000000000303a465b659cbb0ab36ee643ea362c509eeb521300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000479ba509700000000000000000000000000000000000000000000000000000000000000000000000000000000c2ee6b6af7d616f6e27ce7f4a451aedc2b0f5f5c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000479ba509700000000000000000000000000000000000000000000000000000000000000000000000000000000d7f9f54194c633f36ccd5f3da84ad4a1c38cb2cb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000479ba5097000000000000000000000000000000000000000000000000000000000000000000000000000000005d8ba173dc6c3c90c8f7c04c9288bef5fdbad06e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000479ba509700000000000000000000000000000000000000000000000000000000000000000000000000000000f553e6d903aa43420ed7e3bc2313be9286a8f98700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000479ba509700000000000000000000000000000000000000000000000000000000
Proposal ID: 0xa34bdc028de549c0fbd0374e64eb5977e78f62331f6a55f4f2211348c4902d13
```

## EIP-712-Based Off-Chain Message Safe Hashes

Configure the parameters in [`safe_hashes.sh`](./safe_hashes.sh), then run the script:

```console
./safe_hashes.sh
```

The key parameters to configure for an emergency upgrade are:

- `SAFE_MULTISIG_ADDRESS`: Set your Safe multisig address here.
- `PROPOSAL_ID`: Set the calculated proposal ID here.

**Example Output**

```console
Safe message: 0x924182c0ae655857518786673f3026f1c75b754ffbd2716b4af6d78f04745a31
Safe message hash: 0x0b24f0f27141c3cfddcb6748516b026182fba25945dc2b328f32aa0a02229633
Domain hash: 0x63127490E98CEB540DB8DCA78EB231476F5B4061DC5139E45031491BAE94ADDF
Message hash: 0x021DEF418DA3276B5F47AB23C16FFAEA6B962872D2DDF2EBCC88310E203273ED
```

## Standard Upgrade Verification Tools

The scripts in [`standard-upgrades/`](./standard-upgrades) cover upgrades that are _not_ emergency upgrades. Unlike the per-upgrade scripts above, they take their parameters as flags, so the same script works for every upgrade. They compute every hash locally. With `--rpc-url`, they also read the current nonces and cross-check the hashes against the contracts. Run any of them with `--help` for all flags.

### `Governance`-Based Upgrades: Nested Safe Hashes

The ZKsync OS ecosystem `Governance` is owned by the Security Council Safe [`0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63`](https://etherscan.io/address/0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63), whose owners are the Security Council member Safes. A standard upgrade is a transaction of this Safe, and each member Safe approves it in one of two ways:

- `--onchain-tx`: the member Safe executes `approveHash(safeTxHash)` on the Security Council Safe. This is what Safe{Wallet} proposes when a nested Safe confirms a transaction. It uses the member Safe's nonce.
- `--offchain-sig`: the member Safe's owners sign an EIP-1271 `SafeMessage` over the Security Council Safe's transaction, with no on-chain transaction.

[`nested_safe_hashes.sh`](./standard-upgrades/nested_safe_hashes.sh) takes the Safe{Wallet} link of the Security Council Safe's transaction. It loads the transaction from the Safe Transaction Service, recomputes its `safeTxHash` locally and stops if it differs from the one in the link. It prints the calls being approved (a `MultiSend` batch is split into its calls), then what the member Safe's owners sign for either way. Example, `acceptOwnership()` on the `Governance`:

```console
./standard-upgrades/nested_safe_hashes.sh --onchain-tx \
  --member-safe 0xc3Abc9f9AA75Be8341E831482cdA0125a7B1A23e \
  --safe-link 'https://app.safe.global/transactions/tx?safe=eth:0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63&id=multisig_0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63_0x7898029075bd291f12f74ffe481ce0a4339c91e179594fadb173f6936d631a03' \
  --member-nonce 19
```

returns

```console
=== Transactions being approved ===
Call 1:
  to: 0x3d67838307eedEF76026b84170737254A5FaA438
  value: 0 wei
  data: 0x79ba5097
  decoded:
    acceptOwnership()

=== Parent Safe transaction ===
Parent Safe: 0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63 (chain ID 1)
to: 0x3d67838307eedEF76026b84170737254A5FaA438
value: 0
operation: 0 (call)
safeTxGas / baseGas / gasPrice: 0 / 0 / 0
gasToken / refundReceiver: 0x0000000000000000000000000000000000000000 / 0x0000000000000000000000000000000000000000
nonce: 0
Domain hash: 0x380C251E2E51B370FAECA80DCE1028F66465B460588C7488E078601E61E0FE83
Message hash: 0x801356F8395967B55FF8136FF9F45E64D3163F655354676F92081133C9987DEA
safeTxHash: 0x7898029075bd291f12f74ffe481ce0a4339c91e179594fadb173f6936d631a03 (matches the link)

=== Approve on-chain: the member Safe calls `approveHash` on the parent Safe ===
The member Safe sends its own transaction that calls `approveHash(safeTxHash)` on the parent Safe.
It is recorded on-chain and counts as the member's signature when the parent transaction is executed.
It costs gas and uses the member Safe's nonce, so the hashes change if the member Safe executes
anything else first. This is what Safe{Wallet} proposes when a nested Safe confirms a transaction.
The owners of the member Safe sign this transaction of the member Safe:
Member Safe: 0xc3Abc9f9AA75Be8341E831482cdA0125a7B1A23e
to: 0xDF19897e2b3c654A6681d6DC02F5E7cE15205c63
value: 0
data: 0xd4d9bdcd7898029075bd291f12f74ffe481ce0a4339c91e179594fadb173f6936d631a03
  (approveHash(0x7898029075bd291f12f74ffe481ce0a4339c91e179594fadb173f6936d631a03))
operation: 0 (call)
nonce: 19
Domain hash: 0x8A595A96D77E992BB9FF8B20FC59215C86B17154838B5386D6B264728A1F4462
Message hash: 0x608AC06E38F20A236D1220CE4A2E138E445DE9BBB6C40E97D79567070D796C76
safeTxHash: 0xfc69e5001315d483240430f55dadaf20ffca82cea02fc73c639c544ea76d0bdb
```

Function names are looked up with `cast 4byte-decode`, and the arguments are decoded locally. Without the Safe Transaction Service, pass the transaction as `--to`, `--data`, `--value`, `--operation` and `--nonce` instead of `--safe-link`.

### Security Council Approval of Protocol Upgrades

A standard protocol upgrade passes through the `ProtocolUpgradeHandler`, and the Security Council approves it with `SecurityCouncil.approveUpgradeSecurityCouncil`. Each member Safe signs an off-chain `SafeMessage` over the EIP-712 message `ApproveUpgradeSecurityCouncil(bytes32 id)`. [`safe_hashes_security_council_approve_upgrade.sh`](./standard-upgrades/safe_hashes_security_council_approve_upgrade.sh) takes the proposal ID:

```console
./standard-upgrades/safe_hashes_security_council_approve_upgrade.sh \
  --member-safe 0xc3Abc9f9AA75Be8341E831482cdA0125a7B1A23e \
  --proposal-id 0x77d5461c37515d627820ab6573efe63fb0b253cf83308dbb368b859e9835eaaa
```

returns

```console
Proposal ID: 0x77d5461c37515d627820ab6573efe63fb0b253cf83308dbb368b859e9835eaaa
Security Council: 0x59195219d1176E42f8e607e9AC114926D47f9035 (chain ID 1)
Member Safe: 0xc3Abc9f9AA75Be8341E831482cdA0125a7B1A23e
Safe message: 0x86db57b67855110636064406797dbbdc409d97325acf6e943d9b15f25d03e596
Safe message hash: 0x0f54828176de1029d49f1a9e22958a61335188982538359191b57332aef89739
Domain hash: 0x8A595A96D77E992BB9FF8B20FC59215C86B17154838B5386D6B264728A1F4462
Message hash: 0xCD1BA0F46D893CD577A30710F37CDE6543EC1EE960342DD69A56B98340CF1D54
```

With `--rpc-url`, the script also checks that the Safe is a Security Council member and prints the upgrade's state in the `ProtocolUpgradeHandler`. Only a `Waiting` upgrade can be approved.

## 💸 Donation

I am a strong advocate of the open-source and free software paradigm. However, if you feel my work deserves a donation, you can send it to this address: [`0xe9Fa0c8B5d7F79DeC36D3F448B1Ac4cEdedE4e69`](https://etherscan.io/address/0xe9Fa0c8B5d7F79DeC36D3F448B1Ac4cEdedE4e69). I can pledge that I will use this money to help fix more existing challenges in the Ethereum ecosystem 🤝.
