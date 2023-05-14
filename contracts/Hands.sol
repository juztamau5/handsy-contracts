// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

interface IBankroll {
    function receiveFunds() external payable;
}

contract Hands {
    uint constant public BET_MIN = 1e16; // The minimum bet (1 finney)
    uint constant public REVEAL_TIMEOUT = 10 minutes; // Max delay of revelation phase
    uint constant public FEE_PERCENTAGE = 5; // The percentage of user wagers to be sent to the Bankroll contract
    uint constant public MAX_POINTS_PER_ROUND = 3; // The maximum number of points per round

    IBankroll private bankrollContract;

    constructor(address _bankrollContractAddress) {
        bankrollContract = IBankroll(_bankrollContractAddress);
    }


    enum Moves {None, Rock, Paper, Scissors}
    enum Outcomes {None, PlayerA, PlayerB, Draw} // Possible outcomes

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
    mapping(uint => uint) private firstReveal;
    mapping(uint => Game) private games;
    mapping(address => uint) public playerGame;
    mapping(uint => uint) public waitingPlayers;

    event PlayersMatched(uint indexed gameId, address indexed playerA, address indexed playerB);
    event PlayerRegistered(uint indexed gameId, address indexed playerAddress);
    event PlayerWaiting(uint indexed gameId, uint bet);
    event GameOutcome(uint indexed gameId, Outcomes outcome);
    event MoveCommitted(uint indexed gameId, address indexed playerAddress, uint round);
    event NewRound(uint indexed gameId, uint round, uint pointsA, uint pointsB);
    event MoveRevealed(uint indexed gameId, address indexed playerAddress, Moves move, uint round);

    modifier validBet() {
        require(msg.value >= BET_MIN, "Bet must be at least the minimum bet amount");
        _;
    }

    modifier isNotAlreadyInGame() {
        require(playerGame[msg.sender] == 0, "Player already in game");
        _;
    }

    function _generateGameId() private returns (uint) {
        lastGameId += 1;
        return lastGameId;
    }

    function register() public payable validBet isNotAlreadyInGame returns (uint) {
        uint bet = msg.value;
        uint gameId;

        if (waitingPlayers[bet] != 0) {
            gameId = waitingPlayers[bet];
            waitingPlayers[bet] = 0;
            games[gameId].playerB = payable(msg.sender);
            playerGame[msg.sender] = gameId;
            emit PlayersMatched(gameId, games[gameId].playerA, games[gameId].playerB);
        } else {
            gameId = _generateGameId();
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

    //send the encrypted move to the contract
    function commit(uint gameId, bytes32 encrMove) public isRegistered(gameId) {
        Game storage game = games[gameId];
        require(msg.sender == game.playerA || msg.sender == game.playerB, "Player not in game");
        if (msg.sender == game.playerA) {
            require(game.encrMovePlayerA == 0x0, "Player already committed");
            game.encrMovePlayerA = encrMove;
        } else {
            require(game.encrMovePlayerB == 0x0, "Player already committed");
            game.encrMovePlayerB = encrMove;
        }
        emit MoveCommitted(gameId, msg.sender, game.round);
    }

    modifier isRegistered(uint gameId) {
        require(playerGame[msg.sender] == gameId, "Player not registered");
        _;
    }

    modifier commitPhaseEnded(uint gameId) {
        require(games[gameId].playerA != address(0) && games[gameId].playerB != address(0), "Commit phase not ended");
        _;
    }

    modifier hasNotRevealed(uint gameId) {
        require(msg.sender == games[gameId].playerA && games[gameId].movePlayerA == Moves.None ||
                msg.sender == games[gameId].playerB && games[gameId].movePlayerB == Moves.None,
                "Player already revealed");
        _;
    }

    function reveal(uint gameId, string memory clearMove) public isRegistered(gameId) commitPhaseEnded(gameId) hasNotRevealed(gameId) returns (Moves) {
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

        if (firstReveal[gameId] == 0) {
            firstReveal[gameId] = block.timestamp;
        }

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

    modifier revealPhaseEnded(uint gameId) {
        require((games[gameId].movePlayerA != Moves.None && games[gameId].movePlayerB != Moves.None) ||
                (firstReveal[gameId] != 0 && block.timestamp > firstReveal[gameId] + REVEAL_TIMEOUT),
                "Reveal phase not ended");
        _;
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
            if(game.pointsA == MAX_POINTS_PER_ROUND) {
                winner = game.playerA;
            } else {
                winner = game.playerB;
            }

            emit GameOutcome(gameId, outcome);

            _payWinner(gameId, winner);
            _resetGame(gameId);
        }

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

    function _payWinner(uint gameId, address winner) private {
        uint total = games[gameId].bet * 2;
        uint fee = (total * FEE_PERCENTAGE) / 100; // Calculate the fee
        uint payout = total - fee;

        // Transfer the fee to the Bankroll contract
        bankrollContract.receiveFunds{value: fee}();

        //Pay winner
        (bool success, ) = winner.call{value: payout}("");
        require(success, "Transfer to Winner failed");
        
    }

    function _resetGame(uint gameId) private {
        delete playerGame[games[gameId].playerA];
        delete playerGame[games[gameId].playerB];
        delete games[gameId];
        delete firstReveal[gameId];
    }

    function _resetRound(uint gameId) private {
        Game storage game = games[gameId];
        game.movePlayerA = Moves.None;
        game.movePlayerB = Moves.None;
        game.encrMovePlayerA = 0x0;
        game.encrMovePlayerB = 0x0;
        delete firstReveal[gameId];
    }
}
