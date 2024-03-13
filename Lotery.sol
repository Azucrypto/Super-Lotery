// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './SLToken.sol';
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract SuperLottery is VRFConsumerBaseV2 {
    // Événements
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event LotteryDrawingStarted();
    event LotteryDrawingFinished(address winnerAddress);
    event LotteryOpened();
    event LotteryClosed();

    // Struct pour gérer le statut des requêtes
    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    // Variables d'état
    mapping(uint256 => RequestStatus) public s_requests;
    VRFCoordinatorV2Interface private COORDINATOR;
    uint64 private s_subscriptionId;
    address private vrfCoordinator = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;
    bytes32 private keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint32 private callbackGasLimit = 1000000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;
    SLToken private SLT;
    uint private constant MAX_PLAYERS = 4;
    mapping(uint => address) public winners;
    uint public idLottery;
    address payable[] public players;
    address payable private owner;
    mapping(address => bool) public isPlayerRegistered;
    bool public lotteryOpen = true; // Ajout pour gérer l'état d'ouverture de la loterie

    // Constructeur
    constructor(uint64 subscriptionId, SLToken _SLT) VRFConsumerBaseV2(vrfCoordinator) {
        SLT = _SLT;
        owner = payable(msg.sender);
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
    }

    // Fonctions
    function requestRandomWords() internal {
        emit LotteryDrawingStarted();
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords
        );
        s_requests[requestId] = RequestStatus({randomWords: new uint256[](0), exists: true, fulfilled: false});
        emit RequestSent(requestId, numWords);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;

        if (players.length == MAX_PLAYERS) {
            pickWinner(_randomWords[0]);
        }
        
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function pickWinner(uint256 randomResult) internal {
        uint256 index = randomResult % MAX_PLAYERS;
        address payable winner = players[index];
        
        uint256 winnerShare = address(this).balance * 90 / 100;
        winner.transfer(winnerShare);
        owner.transfer(address(this).balance); // Envoyer le reste au propriétaire
        
        SLT.mint(winner, 10 * 10**18);
        winners[idLottery++] = winner;
        emit LotteryDrawingFinished(winner);

        resetLottery();
    }

    function resetLottery() internal {
        for (uint i = 0; i < players.length; i++) {
            isPlayerRegistered[players[i]] = false;
        }
        players = new address payable[](0);
        lotteryOpen = true; // Réouvrir la loterie
        emit LotteryOpened();
    }

    function enter() external payable {
        require(lotteryOpen, "Lottery is Closed");
        require(msg.value == 0.001 ether, "Not enough funds provided");
        require(players.length < MAX_PLAYERS, "Lottery is full");
        require(!isPlayerRegistered[msg.sender], "Player already registered");

        players.push(payable(msg.sender));
        isPlayerRegistered[msg.sender] = true;

        if (players.length == MAX_PLAYERS) {
            lotteryOpen = false; // Fermer la loterie
            emit LotteryClosed();
            requestRandomWords();
        }
    }

    // Accesseurs et autres fonctions
    function getBalance() external view returns(uint) {
        return address(this).balance;
    }

    function getWinner(uint _idLottery) external view returns(address) {
        return winners[_idLottery];
    }

    function getNumberOfPlayers() public view returns (uint) {
        return players.length;
    }

    // Modificateurs
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
}
