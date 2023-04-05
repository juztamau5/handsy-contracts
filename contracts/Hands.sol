// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

contract Hands {
    uint constant public BET_MIN = 1e16; // The minimum bet (1 finney)
    uint constant public REVEAL_TIMEOUT = 10 minutes; // Max delay of revelation phase

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
    }

    uint private nextGameId;
    mapping(uint => uint) private firstReveal;
    mapping(uint => Game) private games;
    mapping(address => uint) public playerGame;
    mapping(uint => uint) public waitingPlayers;

    event PlayersMatched(uint indexed gameId, address indexed playerA, address indexed playerB);
    event PlayerRegistered(uint indexed gameId, address indexed playerAddress);
    event PlayerWaiting(uint indexed gameId, uint bet);
    event GameOutcome(uint indexed gameId, Outcomes outcome);
    event MoveCommitted(uint indexed gameId, address indexed playerAddress);
    event MoveRevealed(uint indexed gameId, address indexed playerAddress, Moves move);

    modifier validBet() {
        require(msg.value >= BET_MIN, "Bet must be at least the minimum bet amount");
        _;
    }

    function register(bytes32 encrMove) public payable validBet returns (uint) {
        uint gameId = playerGame[msg.sender];
        require(gameId == 0, "Player already registered");

        gameId = nextGameId;
        nextGameId++;

        games[gameId].playerA = payable(msg.sender);
        games[gameId].bet = msg.value;
        games[gameId].encrMovePlayerA = encrMove;
        playerGame[msg.sender] = gameId;

        emit PlayerRegistered(gameId, msg.sender);

        _matchPlayers(gameId);

        return gameId;
    }

    function _matchPlayers(uint gameId) private {
        uint bet = games[gameId].bet;

        // If there is a player waiting for the same bet amount, match them
        if (waitingPlayers[bet] != 0) {
            uint opponentGameId = waitingPlayers[bet];
            waitingPlayers[bet] = 0;

            games[gameId].playerB = games[opponentGameId].playerA;
            games[gameId].encrMovePlayerB = games[opponentGameId].encrMovePlayerA;
            playerGame[games[opponentGameId].playerA] = gameId;

            delete games[opponentGameId];

            emit PlayersMatched(gameId, games[gameId].playerA, games[gameId].playerB);
        } else {
            waitingPlayers[bet] = gameId;
            emit PlayerWaiting(gameId, bet);
        }
    }

    modifier isRegistered(uint gameId) {
        require(playerGame[msg.sender] == gameId, "Player not registered");
        _;
    }

    modifier commitPhaseEnded(uint gameId) {
        require(games[gameId].playerA != address(0) && games[gameId].playerB != address(0), "Commit phase not ended");
        _;
    }

    function reveal(uint gameId, string memory clearMove) public isRegistered(gameId) commitPhaseEnded(gameId) returns (Moves) {
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

        emit MoveRevealed(gameId, msg.sender, move);

        if (firstReveal[gameId] == 0) {
            firstReveal[gameId] = block.timestamp;
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

    function getOutcome(uint gameId) public isRegistered(gameId) revealPhaseEnded(gameId) returns (Outcomes) {
        Game storage game = games[gameId];
        Outcomes outcome = _computeOutcome(game.movePlayerA, game.movePlayerB);
        emit GameOutcome(gameId, outcome);

        _payWinners(gameId, outcome);
        _resetGame(gameId);

        return outcome;
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

    function _payWinners(uint gameId, Outcomes outcome) private {
        uint total = games[gameId].bet * 2;
        if (outcome == Outcomes.PlayerA) {
            games[gameId].playerA.transfer(total);
        } else if (outcome == Outcomes.PlayerB) {
            games[gameId].playerB.transfer(total);
        } else { // Draw
            games[gameId].playerA.transfer(games[gameId].bet);
            games[gameId].playerB.transfer(games[gameId].bet);
        }
    }

    function _resetGame(uint gameId) private {
        delete playerGame[games[gameId].playerA];
        delete playerGame[games[gameId].playerB];
        delete games[gameId];
        delete firstReveal[gameId];
    }
}
