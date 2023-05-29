# Protocol Specification

This document specifies the Monkrush protocol implemented fully as smart contracts in Solidity.

## DATA STRUCTURES

**Balances** are onchain data structures which track a user's balance in a given asset.

```
mapping((address => address) => uint256) balances; // (user=>asset)=>amount
```

**Channels** are onchain data structures that define a specific relationship between two parties. Channels are keyed by a unique `channelId`.

```
struct Channel {
    uint32 uid;
    address sender;
    address receiver;
    address asset;
    uint256 credit;
}
```

```
bytes32 channelId = hash(channel); // TODO cleanup for doc
```

```
mapping(bytes32 => Channel) channels; // channelId=>channel
```

**Updates** are updates to balances (tracked as a `debit`) in a given channel.

```
struct Update {
    bytes32 channelId;
    uint256 debit;
    bool isFinal;
}
```

**Packets** are offchain data structures which are stored and transported between peers in Monkrush. They consist of an `Update` and a `proof` (ECDSA signature on the update).

```
struct Packet {
    Update update;
    bytes calldata proof;
}
```

## FUNCTIONS

deposit()
- Takes in tokens or ETH from another chain
- Adds to UserBalance
- Emit event

create()
- Creates channel
- Subtracts from UserBalance
- Emits event

settle()
- Takes in proof
- Verifies signature
    - If sender, signature must have a final flag on it
    - If receiver, assume highest bal sig
    - Replay attacks? => Sender incentivized. Must check msg.sender then?
- Updates UserBalances
- deletes channel
- Emits event

withdraw()
- Reduces balance by amount
- sends user amount in asset back to other chain
- Emits event

pay()
- Gets Channel
- Update balances
- Generate proof
- Update proof
- Update channel
- Output payment packet

receive()
- Gets channel
- Verify proof
- Verify amount is greater
- Update balances + proof
- Update channel

## DEPEDENCIES

Store
- Must be passed in via interface
- Implementer is responsible for writing mappings to whatever store they use

Transport
- No assumptions are made about message transport
- Protocol outputs payment packet that can be sent via any networking. (Recommended: HTTP)

Agent
- Made up of offchain codebase
- Simple Go module that fits neatly into existing stores
*/