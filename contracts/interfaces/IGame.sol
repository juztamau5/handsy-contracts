// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

interface IGameplay {
    // Register a new game, making the sender Player A and placing them on the waiting list
    // Returns the game id
    function register() external payable returns (uint);
    
    // Commit a hashed move to the current game
    function commit(uint gameId, bytes32 encrMove) external;
    
    // Reveal a move in the current game, given the move in plaintext
    // Returns the numerical representation of the move
    function reveal(uint gameId, string calldata clearMove) external returns (uint);
    
    // Helper function to convert the first character of a string to an integer
    // Returns the numerical representation of the character
    function getFirstChar(string calldata str) external pure returns (uint);
    
    // Get the details of a game given the game id
    // Returns the addresses of player A and player B, the bet amount, the hashed moves of each player, the plain moves of each player,
    // the round number, and the points of each player
    function getGameDetails(uint gameId) external view returns (address playerA, address playerB, uint bet, bytes32 encrMovePlayerA, bytes32 encrMovePlayerB, uint movePlayerA, uint movePlayerB, uint round, uint pointsA, uint pointsB);
    
    // Get the game id of a given player
    // Returns the game id
    function getPlayerGame(address player) external view returns (uint);
    
    // Get the game id of a waiting player given a bet amount
    // Returns the game id
    function getWaitingPlayers(uint bet) external view returns (uint);

    // Emitted when two players have been matched for a game
    event PlayersMatched(uint indexed gameId, address indexed playerA, address indexed playerB);
    
    // Emitted when a player has registered for a game
    event PlayerRegistered(uint indexed gameId, address indexed playerAddress);
    
    // Emitted when a player is waiting for a match
    event PlayerWaiting(uint indexed gameId, uint bet);
    
    // Emitted when a game has concluded
    event GameOutcome(uint indexed gameId, uint outcome);
    
    // Emitted when a player commits a move
    event MoveCommitted(uint indexed gameId, address indexed playerAddress, uint round);
    
    // Emitted at the start of a new round
    event NewRound(uint indexed gameId, uint round, uint pointsA, uint pointsB);
    
    // Emitted when a player reveals their move
    event MoveRevealed(uint indexed gameId, address indexed playerAddress, uint move, uint round);
}