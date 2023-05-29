/* TODO 
    Figure out simplest strategy for finalizing channels as sender. 

    Options:

    1. Channels with fixed expiry time. Tradeoffs:
        - Requires offchain tracking to determine which channels are expired and settle them.
        - Need to consider cases where receiver may not effectively track + settle.
    2. isFinal flag. Tradeoffs:
        - Does it actually work? Sender can just sign final flag on old state.
        - Only way to be sure is for counterparty to sign. Ick, extra overhead.
        - But then what happens if receiver doesn't sign?
    3. Sender can settle after timer. Tradeoffs:
        - No instant exit for sender - ok?
        - Requires two steps to complete settlement - ick
    
    Any other options?
*/
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*
Monkrush is an simple, ultra-scalable micropayment system. 
*/

contract Monkrush { //TODO reentrancy management

using ECDSA for bytes32;

    // Onchain data structure
    struct Channel {
        uint32 uid;
        address sender;
        address receiver;
        address asset;
        uint256 credit;
    }

    // Offchain data structures

    struct Update {
        bytes32 channelId;
        uint256 debit;
        bool isFinal;
    }

    struct Packet {
        Update update;
        bytes proof;
    }

    mapping(address => mapping(address => uint256)) public balances;
    mapping(bytes32 => Channel) public channels;

    // EVENTS

    event Deposited(
        uint256 amount,
        address user,
        address asset,
        uint256 balance
    );

    event Created(
        uint32 uid, 
        address indexed sender, 
        address indexed receiver, 
        address asset,
        uint256 credit
    );

    event Settled(
        uint32 uid, 
        address indexed sender, 
        address indexed receiver,
        address asset,  
        uint256 credit,
        uint256 amount,
        bytes proof
    );

    event Withdrawn(
        uint256 amount,
        address user,
        address asset,
        uint256 balance
    );

    // FUNCTIONS

    function deposit (
        uint256 amount,
        address user,
        address asset
    ) external returns(uint256) {
        // Pull tokens into contract
        // TODO make it only possible to use WETH on rollup
        // TODO also consider making deposit a precompile?
        balances[user][asset] = balances[user][asset] + amount;
        return (balances[user][asset]);
        emit Deposited(amount, user, asset, balances[user][asset]);
    }

    function create(
        uint32 uid,
        address sender,
        address receiver,
        address asset,
        uint256 credit
    ) external returns(Packet) {
        // Create channel
        Channel channel = Channel({
            uid: uid,
            sender: sender,
            receiver: receiver,
            asset: asset,
            credit: credit
        });
        bytes32 channelId = getChannelIdFromChannel(channel);

        // Ensure channel doesn't exist
        require(uid != bytes32(0), "Uid cannot be empty");
        require(channels[channelId].uid == bytes32(0), "Channel must not exist");
        require(msg.sender = sender, "Channel creator must be sender"); //TODO gas abstraction?

        // Update user balance
        balances[sender][asset] = balances[sender][asset] - credit;

        // Set channel
        channels[channelId] = channel;

        // Create initial packet
        Update update = Update({
            channelId: channelId,
            debit: 0,
            isFinal: false
        });
        Packet packet = Packet({
            update: update,
            proof: bytes(0)
        });

        emit Created(uid, sender, receiver, msg.value);
        return(packet);
    }

    function settle(
        Packet packet
    ) external {
        Channel channel = channels[packet.update.channelId];
        require(channel.uid != bytes32(0), "Channel must exist");
        if(msg.sender == channel.sender) {
            require(packet.update.isFinal);
        }

        bytes32 message = prefixed(keccak256(abi.encodePacked(packet)));

        // Verify sig
        require(message.recover(packet.proof) == channel.sender, "Invalid signature");

        // Packet user balance and delete channel
        balances[channel.receiver][channel.asset] = balances[channel.receiver][channel.asset] + packet.update.debit;
        balances[channel.sender][channel.asset] = balances[channel.sender][channel.asset] + channel.credit - packet.update.debit;
        delete channels[packet.update.channelId];
        emit Settled(
            channel.uid, 
            channel.sender, 
            channel.receiver, 
            channel.credit,
            channel.asset,
            packet.update.debit,
            packet.proof
        );
    }

    function withdraw() external returns(uint256) {
        // TODO use connext here? Or just have a specific xReceiver?
    }
    
    // OFFCHAIN FUNCTIONS


    // TODO this needs to be rewritten
    function pay(
        Packet packet,
        uint256 amount,
        bool isFinal
    ) external view returns (Packet, Update) {
        require(channels[packet.update.channelId].uid != bytes32(0), "Channel must exist");
        require(update.packet.debit + amount <= channels[packet.update.channelId].credit);
        // Packet channel balances
        packet.debit = packet.debit + amount;
        packet.isFinal = isFinal;

        // Generate proof
        bytes32 message = prefixed(keccak256(abi.encodePacked(packet)));
        bytes proof; // TODO generate signature

        Update update = Update({
            packet: packet,
            proof: proof
        });
        return (packet, update);
    }

    function verify(
        Packet oldPacket,
        Packet newPacket // TODO is this correct?
    ) external view returns (Packet) {
        require(channels[packet.update.channelId].uid != bytes32(0), "Channel must exist");
        require(update.packet.debit <= channel[update.packet.channelId].credit, "Debit must be lower than credit");
        require(packet.debit <= update.packet.debit, "Debit can only increase");
        require(!packet.isFinal, "Cannot update finalized channel");

       // Packet channel balances
        packet.debit = packet.debit + update.packet.amount;
        packet.isFinal = update.packet.isFinal;

        // Verify proof
        bytes32 proofHash = prefixed(keccak256(abi.encodePacked(packet)));
        require(proofHash.recover(update.proof) == channel[update.packet.channelId].sender, "Invalid signature");

        return packet;
    }

    // INTERNAL FNS

    function getChannelIdFromChannel(Channel channel) internal view returns (bytes32) {
        return (keccak256(abi.encodePacked(channel)));
    }

    function prefixed(bytes32 message) internal pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(message);
    }
}