// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PongGame
 * @notice Pong multiplayer on ApexFusion Nexus.
 *
 *  - Both players pay 1 AP3X when creating / joining a game.
 *  - Winner receives 94% of the pot (1.88 AP3X from 2 AP3X total).
 *  - 6% covers gas costs and game infrastructure maintenance.
 *  - Pull pattern: winnings accumulate in pendingWithdrawals — withdraw anytime.
 *  - Timeout: 5 minutes of inactivity → other player wins automatically.
 *  - If no opponent joins — creator can cancel and get their entry fee back.
 *  - adminCancel: infra can cancel any stuck game at any state.
 */
contract PongGame {

    enum GameState { Waiting, Active, Finished, Cancelled }

    struct Game {
        address player1;
        address player2;
        address winner;
        GameState state;
        uint256 pot;
        uint256 createdAt;
        uint256 lastActivityAt;
    }

    address private _infra;
    uint256 public entryFee;
    uint256 public feeBps = 600;
    uint256 public gameTimeout = 5 minutes;

    uint256 private _gameCounter;
    mapping(uint256 => Game)    public games;
    mapping(address => uint256) public playerActiveGame;
    mapping(address => uint256) public pendingWithdrawals;

    event GameCreated(uint256 indexed gameId, address indexed player1, uint256 entryFee);
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event GameFinished(uint256 indexed gameId, address indexed winner, uint256 prize);
    event GameCancelled(uint256 indexed gameId, address indexed by);
    event ActivityPinged(uint256 indexed gameId, address indexed player);
    event Withdrawn(address indexed player, uint256 amount);

    error WrongEntryFee(uint256 sent, uint256 required);
    error GameNotFound(uint256 gameId);
    error GameNotWaiting(uint256 gameId);
    error GameNotActive(uint256 gameId);
    error GameAlreadyFinished(uint256 gameId);
    error NotAPlayer(uint256 gameId, address caller);
    error AlreadyInGame(address player, uint256 activeGameId);
    error CannotJoinOwnGame();
    error GameNotTimedOut();
    error NothingToWithdraw();
    error TransferFailed();
    error Unauthorized();

    constructor(uint256 _entryFee, address infraAddress) {
        _infra = infraAddress;
        entryFee = _entryFee;
    }

    modifier onlyInfra() {
        if (msg.sender != _infra) revert Unauthorized();
        _;
    }

    // ─── Player Actions ──────────────────────────────────────────────────────

    function createGame() external payable returns (uint256 gameId) {
        if (msg.value != entryFee) revert WrongEntryFee(msg.value, entryFee);
        if (playerActiveGame[msg.sender] != 0)
            revert AlreadyInGame(msg.sender, playerActiveGame[msg.sender]);

        _gameCounter++;
        gameId = _gameCounter;
        games[gameId] = Game({
            player1:        msg.sender,
            player2:        address(0),
            winner:         address(0),
            state:          GameState.Waiting,
            pot:            msg.value,
            createdAt:      block.timestamp,
            lastActivityAt: block.timestamp
        });
        playerActiveGame[msg.sender] = gameId;
        emit GameCreated(gameId, msg.sender, entryFee);
    }

    function joinGame(uint256 gameId) external payable {
        Game storage g = games[gameId];
        if (g.player1 == address(0))      revert GameNotFound(gameId);
        if (g.state != GameState.Waiting) revert GameNotWaiting(gameId);
        if (msg.sender == g.player1)      revert CannotJoinOwnGame();
        if (msg.value != entryFee)        revert WrongEntryFee(msg.value, entryFee);
        if (playerActiveGame[msg.sender] != 0)
            revert AlreadyInGame(msg.sender, playerActiveGame[msg.sender]);

        g.player2        = msg.sender;
        g.state          = GameState.Active;
        g.pot           += msg.value;
        g.lastActivityAt = block.timestamp;
        playerActiveGame[msg.sender] = gameId;
        emit GameJoined(gameId, msg.sender);
    }

    function reportWinner(uint256 gameId, address winner) external {
        Game storage g = games[gameId];
        if (g.state != GameState.Active) revert GameNotActive(gameId);
        if (msg.sender != g.player1 && msg.sender != g.player2)
            revert NotAPlayer(gameId, msg.sender);
        if (winner != g.player1 && winner != g.player2)
            revert NotAPlayer(gameId, winner);
        _finalise(gameId, winner);
    }

    function pingActivity(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.state != GameState.Active) revert GameNotActive(gameId);
        if (msg.sender != g.player1 && msg.sender != g.player2)
            revert NotAPlayer(gameId, msg.sender);
        g.lastActivityAt = block.timestamp;
        emit ActivityPinged(gameId, msg.sender);
    }

    function cancelGame(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.state != GameState.Waiting) revert GameNotWaiting(gameId);
        if (msg.sender != g.player1 && msg.sender != _infra)
            revert NotAPlayer(gameId, msg.sender);

        g.state = GameState.Cancelled;
        delete playerActiveGame[g.player1];
        if (g.pot > 0) {
            pendingWithdrawals[g.player1] += g.pot;
            g.pot = 0;
        }
        emit GameCancelled(gameId, msg.sender);
    }

    function claimTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.state != GameState.Active) revert GameNotActive(gameId);
        if (block.timestamp < g.lastActivityAt + gameTimeout) revert GameNotTimedOut();
        if (msg.sender != g.player1 && msg.sender != g.player2)
            revert NotAPlayer(gameId, msg.sender);
        _finalise(gameId, msg.sender);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Emergency cancel — infra can unstick any game in any state except Finished.
    function adminCancel(uint256 gameId) external onlyInfra {
        Game storage g = games[gameId];
        if (g.player1 == address(0)) revert GameNotFound(gameId);
        if (g.state == GameState.Finished) revert GameAlreadyFinished(gameId);

        g.state = GameState.Cancelled;
        delete playerActiveGame[g.player1];
        if (g.player2 != address(0)) delete playerActiveGame[g.player2];

        if (g.pot > 0) {
            if (g.player2 != address(0)) {
                uint256 half = g.pot / 2;
                pendingWithdrawals[g.player1] += half;
                pendingWithdrawals[g.player2] += g.pot - half;
            } else {
                pendingWithdrawals[g.player1] += g.pot;
            }
            g.pot = 0;
        }
        emit GameCancelled(gameId, msg.sender);
    }

    /// @notice Infra can force-finish a game if both players disconnect.
    function adminFinish(uint256 gameId, address winner) external onlyInfra {
        Game storage g = games[gameId];
        if (g.state != GameState.Active) revert GameNotActive(gameId);
        if (winner != g.player1 && winner != g.player2)
            revert NotAPlayer(gameId, winner);
        _finalise(gameId, winner);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        pendingWithdrawals[msg.sender] = 0;
        _send(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    function getGame(uint256 gameId) external view returns (Game memory) { return games[gameId]; }
    function totalGames() external view returns (uint256) { return _gameCounter; }
    function pendingOf(address player) external view returns (uint256) { return pendingWithdrawals[player]; }

    // ─── Infrastructure Config ────────────────────────────────────────────────

    function setEntryFee(uint256 _fee) external onlyInfra { entryFee = _fee; }
    function setFeeBps(uint256 _bps)   external onlyInfra { require(_bps <= 1500, "max 15%"); feeBps = _bps; }
    function setGameTimeout(uint256 s) external onlyInfra { gameTimeout = s; }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _finalise(uint256 gameId, address winner) internal {
        Game storage g = games[gameId];
        g.winner = winner;
        g.state  = GameState.Finished;
        delete playerActiveGame[g.player1];
        delete playerActiveGame[g.player2];

        uint256 fee   = (g.pot * feeBps) / 10_000;
        uint256 prize = g.pot - fee;

        pendingWithdrawals[winner] += prize;
        pendingWithdrawals[_infra] += fee;
        g.pot = 0;
        emit GameFinished(gameId, winner, prize);
    }

    function _send(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}
