// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

/**imports */
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contract
 * @author Oluwafemi Kolade
 * @notice This contract is for creating a sample raffle
 * @dev Implements chainlink VRFv2
 */

/** */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle_NotEnoughEthSent();
    error Raffle_TransferFailed();
    error Raffle_RaffleNotOpened();
    error Raffle_UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /** Type Declarations */

    enum Raffle_state {
        OPEN,
        Calculating
    }

    /**State Variables */
    uint16 private constant REQUEST_CONFRIMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee; //Entrance feee made immutable and private
    uint256 private immutable i_interval; //Time passed
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; //This address differs from chain to chain
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint256 private s_lastTimeStamp;
    Raffle_state public s_raffleState;
    address payable[] private s_players; //array of addresses of participant of the lottery.
    //It is payable because we still intend to pick a winner and send funds to the address
    address payable s_recentWinner;

    /**EVENTS */
    event EnteredRaffle(address indexed player_address);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = Raffle_state.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee,"Not Enough Eth Sent!");
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }

        if (s_raffleState != Raffle_state.OPEN) {
            revert Raffle_RaffleNotOpened();
        }

        s_players.push(payable(msg.sender)); //pushing msg.sender to the players array, also msg.sender is payable

        emit EnteredRaffle(msg.sender);
    }

    //When is the winner supposed to be picked

    /**
     * @dev This the function the chainlink node calls to see if its time to perform an upkeep
     * The following should be true for the function to return true
     * The time interval must have passed
     * The Raffle state must be opened
     * The contract has ETh i.e players
     * (Implicit) The subscription is funded LINK
     */
    function checkUpkeep(
        bytes memory /*checkdata*/
    ) public view returns (bool UpkeepNeeded, bytes memory /*performdata*/) {
        //check Time Interval
        bool timeHasPasssed = (block.timestamp - s_lastTimeStamp < i_interval);
        bool isOpen = Raffle_state.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        UpkeepNeeded = (timeHasPasssed && isOpen && hasBalance && hasPlayers);
        return (UpkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /*performData*/) external {
        (bool UpkeepNeeded, ) = checkUpkeep("");
        if (!UpkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = Raffle_state.Calculating;

        //Request RNG
        //Get random number

        // Will revert if subscription is not set and funded.
        i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane:Gas price you want to use to generate random words
            i_subscriptionId, //subscription ID funded with LINK or SepoliaETh
            REQUEST_CONFRIMATIONS, //Number of block confirmations you need for your randomNumber
            i_callbackGasLimit, //MAx amount of gas you want to use.To make sure you don't overspend
            NUM_WORDS //Number of Random Numbers
        );
    }

    //CEI Checks Effects Interaction
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomwords
    ) internal override {
        //Checks-> checks are more gas efficient
        //require (if-> errors)

        //Effects: This is where effect our own contract

        //After getting our random number(rng) we can use the modulo operation on the rng to get the index of the winner between the range of the length of the s_players array.
        //s_players.length = 10;
        //rng = 12;
        //index_of_winner = 12%10;
        //index_of_winner = 2;
        uint256 indexOfWinner = randomwords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        s_raffleState = Raffle_state.OPEN;
        //After we've picked our winner we'll have to reset the array since the Raffle state is now opened.

        //Reset array

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        //Interactions: with other contracts: This is to avoid reentrancy attacks

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    //Getter Function for the entrance fee so partcipant can Know the required fee to join the lottery

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (Raffle_state) {
        return s_raffleState;
    }

    function getPlayer(
        uint256 index_of_player
    ) external view returns (address) {
        return s_players[index_of_player];
    }
}
