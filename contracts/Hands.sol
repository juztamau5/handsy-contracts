// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./Bank.sol";
import "hardhat/console.sol";

contract Hands {
    uint constant public BET_MIN = 1e16; // The minimum bet (1 finney)
    uint constant public REVEAL_TIMEOUT = 2 minutes; // Max delay of revelation phase
    uint constant public FEE_PERCENTAGE = 5; // The percentage of user wagers to be sent to the bank contract
    uint constant public MAX_POINTS_PER_ROUND = 3; // The maximum number of points per round
    uint constant public COMMIT_TIMEOUT = 2 minutes; // Max delay of commit phase

    Bank private bankContract;

    constructor(address _bankContractAddress) {
        bankContract = Bank(_bankContractAddress);
    }

    enum Moves {None, Rock, Paper, Scissors}
    enum Outcomes {None, PlayerA, PlayerB, Draw, Left} // Possible outcomes

    struct Game {
        address payable playerA;
        address payable playerB;
        uint bet;
        bytes32 encrMovePlayerA;
        bytes32 encrMovePlayerB;
        Moves movePlayerA;
        Moves movePlayerB;
        uint round;
        uint pointsA;
        uint pointsB;
    }

    uint private lastGameId;
    mapping(uint => uint) private commitPhaseStart;
    mapping(uint => uint) private revealPhaseStart; // Added this to track the time of the first commit
    mapping(uint => Game) private games;
    mapping(address => uint) public playerGame;
    mapping(uint => uint) public waitingPlayers;


    // Events
    event PlayersMatched(uint indexed gameId, address indexed playerA, address indexed playerB);
    event PlayerRegistered(uint indexed gameId, address indexed playerAddress);
    event PlayerWaiting(uint indexed gameId, uint bet);
    event GameOutcome(uint indexed gameId, Outcomes outcome);
    event MoveCommitted(uint indexed gameId, address indexed playerAddress, uint round);
    event NewRound(uint indexed gameId, uint round, uint pointsA, uint pointsB);
    event MoveRevealed(uint indexed gameId, address indexed playerAddress, Moves move, uint round);
    event PlayerLeft(uint indexed gameId, address indexed playerAddress, uint round);
    event PlayerCancelled(uint indexed gameId, address indexed playerAddress);

    // Modifiers
    modifier validBet() { require(msg.value >= BET_MIN, "Bet must be at least the minimum bet amount"); _;}
    modifier isNotAlreadyInGame() { require(playerGame[msg.sender] == 0, "Player already in game"); _;}
    modifier isRegistered(uint gameId) { require(playerGame[msg.sender] == gameId, "Player not registered"); _; }
    modifier commitPhaseEnded(uint gameId) {
        require(games[gameId].encrMovePlayerA != 0x0 && games[gameId].encrMovePlayerB != 0x0 || 
                (commitPhaseStart[gameId] != 0 && block.timestamp > commitPhaseStart[gameId] + COMMIT_TIMEOUT), 
                "Commit phase not ended");
        _;
    }
    modifier isCommitPhase(uint gameId) {
        console.log("Commit phase start: %s", commitPhaseStart[gameId]);
        console.log("Commit phase end: %s", commitPhaseStart[gameId] + COMMIT_TIMEOUT);
        console.log("Current time: %s", block.timestamp);
        if(commitPhaseStart[gameId] != 0 && block.timestamp > commitPhaseStart[gameId] + COMMIT_TIMEOUT) {
            _abruptFinish(gameId);
            return;
        }
        require(games[gameId].encrMovePlayerA == 0x0 || games[gameId].encrMovePlayerB == 0x0, "Commit phase ended");
        _;
    }   
    modifier hasNotRevealed(uint gameId) {
        require(msg.sender == games[gameId].playerA && games[gameId].movePlayerA == Moves.None ||
                msg.sender == games[gameId].playerB && games[gameId].movePlayerB == Moves.None,
                "Player already revealed");
        _;
    }
    modifier isRevealPhase(uint gameId) {
        console.log("Reveal phase start: %s", revealPhaseStart[gameId]);
        console.log("Reveal phase end: %s", revealPhaseStart[gameId] + REVEAL_TIMEOUT);
        console.log("Current time: %s", block.timestamp);
        if (revealPhaseStart[gameId] != 0 && block.timestamp > revealPhaseStart[gameId] + REVEAL_TIMEOUT) {
            _abruptFinish(gameId);
            return;
        }
        require((games[gameId].encrMovePlayerA != 0x0 && games[gameId].encrMovePlayerB != 0x0) ||
                (revealPhaseStart[gameId] != 0 && block.timestamp < revealPhaseStart[gameId] + REVEAL_TIMEOUT),
                "Is not reveal phase");
        _;
    }
    modifier revealPhaseEnded(uint gameId) {
        require((games[gameId].movePlayerA != Moves.None && games[gameId].movePlayerB != Moves.None) ||
                (revealPhaseStart[gameId] != 0 && block.timestamp > revealPhaseStart[gameId] + REVEAL_TIMEOUT),
                "Reveal phase not ended");
        _;
    }

    function register() public payable validBet isNotAlreadyInGame returns (uint) {
        uint bet = msg.value;
        uint gameId;

        console.log("Registering player with bet %s", bet);

        if (waitingPlayers[bet] != 0) {
            gameId = waitingPlayers[bet];
            waitingPlayers[bet] = 0;
            games[gameId].playerB = payable(msg.sender);
            playerGame[msg.sender] = gameId;
            commitPhaseStart[gameId] = block.timestamp;
            emit PlayersMatched(gameId, games[gameId].playerA, games[gameId].playerB);
        } else {
            lastGameId += 1;
            gameId = lastGameId;
            games[gameId] = Game({
                playerA: payable(msg.sender),
                playerB: payable(address(0)),
                bet: bet,
                encrMovePlayerA: 0x0,
                encrMovePlayerB: 0x0,
                movePlayerA: Moves.None,
                movePlayerB: Moves.None,
                round: 0,
                pointsA: 0,
                pointsB: 0
            });
            playerGame[msg.sender] = gameId;
            waitingPlayers[bet] = gameId;
            emit PlayerWaiting(gameId, bet);
        }

        emit PlayerRegistered(gameId, msg.sender);
        return gameId;
    }

    function cancel(uint gameId) public {
        Game storage game = games[gameId];
        require(game.playerA == msg.sender && game.playerB == payable(address(0)), "Cannot cancel this game");

        (bool success, ) = payable(msg.sender).call{value: game.bet}("");
        require(success, "Transfer failed");

        emit PlayerCancelled(gameId, msg.sender);

        delete playerGame[game.playerA];
        delete playerGame[game.playerB];
        delete playerGame[msg.sender];
        delete waitingPlayers[game.bet];
        delete games[gameId];
    }

    function leave(uint gameId) public isRegistered(gameId) {
        Game storage game = games[gameId];
        require(game.playerA == msg.sender || game.playerB == msg.sender, "Not player of this game");

        // Pay remaining player
        address remainingPlayer = game.playerA == msg.sender ? game.playerB : game.playerA;
        _payWinner(gameId, remainingPlayer, msg.sender);

        //Set removed player to address(0)
        if (game.playerA == msg.sender) {
            game.playerA = payable(address(0));
        } else {
            game.playerB = payable(address(0));
        }

        emit GameOutcome(gameId, Outcomes.Left);

        delete playerGame[game.playerA];
        delete playerGame[game.playerB];
        delete playerGame[msg.sender];
        delete waitingPlayers[game.bet];
        delete games[gameId];

        
    }

    //send the encrypted move to the contract
    function commit(uint gameId, bytes32 encrMove) public isRegistered(gameId) isCommitPhase(gameId) {
        Game storage game = games[gameId];
        require(msg.sender == game.playerA || msg.sender == game.playerB, "Player not in game");
        if (msg.sender == game.playerA) {
            require(game.encrMovePlayerA == 0x0, "Player already committed");
            game.encrMovePlayerA = encrMove;
        } else {
            require(game.encrMovePlayerB == 0x0, "Player already committed");
            game.encrMovePlayerB = encrMove;
        }

        //Check if last player committed
        //If so, start reveal phase
        if (game.encrMovePlayerA != 0x0 && game.encrMovePlayerB != 0x0) {
            revealPhaseStart[gameId] = block.timestamp;
        }

        emit MoveCommitted(gameId, msg.sender, game.round);
    }

    function reveal(uint gameId, string memory clearMove) public isRegistered(gameId) commitPhaseEnded(gameId) hasNotRevealed(gameId) isRevealPhase(gameId) returns (Moves) {
        bytes32 encrMove = sha256(abi.encodePacked(clearMove));
        Moves move = Moves(getFirstChar(clearMove));

        if (move == Moves.None) {
            revert("Invalid move");
        }
            Game storage game = games[gameId];

        if (msg.sender == game.playerA) {
            require(game.encrMovePlayerA == encrMove, "Encrypted move does not match");
            game.movePlayerA = move;
        } else {
            require(game.encrMovePlayerB == encrMove, "Encrypted move does not match");
            game.movePlayerB = move;
        }

        emit MoveRevealed(gameId, msg.sender, move, game.round);

        // if (firstReveal[gameId] == 0) {
        //     firstReveal[gameId] = block.timestamp;
        // }

        //call getOutcome if both players have revealed their moves
        if (game.movePlayerA != Moves.None && game.movePlayerB != Moves.None) {
            _getOutcome(gameId);
        }

        return move;
    }

    function getFirstChar(string memory str) private pure returns (uint) {
        bytes1 firstByte = bytes(str)[0];
        if (firstByte == 0x31) {
            return 1;
        } else if (firstByte == 0x32) {
            return 2;
        } else if (firstByte == 0x33) {
            return 3;
        } else {
            return 0;
        }
    }

    function _handleRound(uint gameId, Outcomes outcome) private {
        Game storage game = games[gameId];

        //update points
        if (outcome == Outcomes.PlayerA) {
            game.pointsA += 1;
        } else if (outcome == Outcomes.PlayerB) {
            game.pointsB += 1;
        }

        game.round += 1;

        emit NewRound(gameId, game.round, game.pointsA, game.pointsB);
        
        _resetRound(gameId);


        //check if game is over
        if(game.pointsA == MAX_POINTS_PER_ROUND || game.pointsB == MAX_POINTS_PER_ROUND) {
            //get winner
            address payable winner;
            address payable loser;
            if(game.pointsA == MAX_POINTS_PER_ROUND) {
                winner = game.playerA;
                loser = game.playerB;
            } else {
                winner = game.playerB;
                loser = game.playerA;
            }

            emit GameOutcome(gameId, outcome);

            _payWinner(gameId, winner, loser);
            _resetGame(gameId);
        }
    }

    function _abruptFinish(uint gameId) private {
        //Check who has not revealed or committed
        Game storage game = games[gameId];
        bool playerACommited = game.encrMovePlayerA != 0x0;
        bool playerBCommited = game.encrMovePlayerB != 0x0;
        bool playerARevealed = game.movePlayerA != Moves.None;
        bool playerBRevealed = game.movePlayerB != Moves.None;
        
        address payable winningPlayer;
        address payable stalledPlayer;
        bool bothStalled = false;

        //if both players have not committed, refund both
        if (!playerACommited && !playerBCommited) {
            winningPlayer = game.playerA;
            stalledPlayer = game.playerB;
            bothStalled = true;
        } else if (!playerACommited) {
            winningPlayer = game.playerB;
            stalledPlayer = game.playerA;
        } else if (!playerBCommited) {
            winningPlayer = game.playerA;
            stalledPlayer = game.playerB;
        } else if (!playerARevealed && !playerBRevealed) {
            winningPlayer = game.playerA;
            stalledPlayer = game.playerB;
            bothStalled = true;
        } else if (!playerARevealed) {
            winningPlayer = game.playerB;
            stalledPlayer = game.playerA;
        } else if (!playerBRevealed) {
            winningPlayer = game.playerA;
            stalledPlayer = game.playerB;
        }

        emit GameOutcome(gameId, Outcomes.None);

        if (bothStalled) {
            _refund(gameId, winningPlayer, stalledPlayer);
        } else {
            _payWinner(gameId, winningPlayer, stalledPlayer);
        }

        //reset game
        _resetGame(gameId);

    }

    function _getOutcome(uint gameId) private isRegistered(gameId) revealPhaseEnded(gameId) returns (Outcomes) {
        Game storage game = games[gameId];
        Outcomes outcome = _computeOutcome(game.movePlayerA, game.movePlayerB);

        _handleRound(gameId, outcome);

    }

    function _computeOutcome(Moves moveA, Moves moveB) private pure returns (Outcomes) {
        if (moveA == moveB) {
            return Outcomes.Draw;
        } else if ((moveA == Moves.Rock && moveB == Moves.Scissors) ||
                (moveA == Moves.Paper && moveB == Moves.Rock) ||
                (moveA == Moves.Scissors && moveB == Moves.Paper)) {
            return Outcomes.PlayerA;
        } else {
            return Outcomes.PlayerB;
        }
    }

    function _payWinner(uint gameId, address winner, address loser) private {
        uint total = games[gameId].bet * 2;
        uint fee = (total * FEE_PERCENTAGE) / 100; // Calculate the fee
        uint payout = total - fee;

        // Transfer the fee to the bank contract
        bankContract.receiveFunds{value: fee}(winner, loser);

        //Pay winner
        (bool success, ) = winner.call{value: payout}("");
        require(success, "Transfer to Winner failed");
        
    }

    //function _refund similar to _paywinner still takes a fee for bankContract
    function _refund(uint gameId, address payable playerA, address payable playerB) private {
        uint total = games[gameId].bet * 2;
        uint fee = (total * FEE_PERCENTAGE) / 100; // Calculate the fee
        uint payout = total - fee;

        // Transfer the fee to the bank contract
        bankContract.receiveFunds{value: fee}(playerA, playerB);

        //Pay players
        (bool success, ) = playerA.call{value: payout / 2}("");
        require(success, "Transfer to Player A failed");
        (success, ) = playerB.call{value: payout / 2}("");
        require(success, "Transfer to Player B failed");
    }

    function _resetGame(uint gameId) private {
        delete playerGame[games[gameId].playerA];
        delete playerGame[games[gameId].playerB];
        delete games[gameId];
        delete commitPhaseStart[gameId];
        delete revealPhaseStart[gameId];
    }

    function _resetRound(uint gameId) private {  
        Game storage game = games[gameId];
        game.movePlayerA = Moves.None;
        game.movePlayerB = Moves.None;
        game.encrMovePlayerA = 0x0;
        game.encrMovePlayerB = 0x0;
        commitPhaseStart[gameId] = block.timestamp;
        delete revealPhaseStart[gameId];
    }
}
