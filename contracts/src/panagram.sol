// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {IVerifier} from "./verifier.sol";

contract Panagram is ERC1155, Ownable {
    event VerifierUpdated(address indexed oldAddr, address indexed newAddr);
    event NewRoundStarted(uint256 indexed newRound, uint256 indexed previousRound, uint256 startedAt);
    event WinnerOfRound(uint256 indexed round, address indexed winner, uint256 nftId);
    event RunnerUpOfRound(uint256 indexed round, address indexed player, uint256 nftId);

    string public constant BASE_URI =
        "https://white-brilliant-hyena-447.mypinata.cloud/ipfs/bafybeibrfgpvybqk6kf5okqfrqms3c7g63cgme32cuh5unzsg6pcyg3ade/";
    uint256 public constant WINNER_NFT_ID = 0;
    uint256 public constant RUNNERUP_NFT_ID = 1;

    IVerifier public verifier;
    uint256 public currentRound;
    uint256 public roundStartedAt;
    uint256 public eachRoundTime = 10 minutes;

    // The answer for each round. Only the hash is ever stored or transmitted.
    mapping(uint256 round => bytes32 answerHash) public roundAnswerHash;
    mapping(address user => mapping(uint256 round => bool)) public userWonRound;
    mapping(uint256 round => bool) public roundHasWinner;
    

    constructor(address _verifier) ERC1155("") Ownable(msg.sender) {
        require(_verifier != address(0), "zero verifier");
        verifier = IVerifier(_verifier);
    }

    function setVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "zero verifier");
        address oldAddr = address(verifier);
        verifier = IVerifier(_verifier);
        emit VerifierUpdated(oldAddr, _verifier);
    }

    /// @param answerHash keccak256(abi.encodePacked(word)), computed off-chain.
    ///        The plain word must never appear in calldata.
    function startNewRound(bytes32 answerHash) external onlyOwner {
        require(answerHash != bytes32(0), "empty answer");

        if (currentRound >= 1) {
            require(roundHasWinner[currentRound], "current round has no winner");
            require(block.timestamp - roundStartedAt > eachRoundTime, "round time still left");
        }

        uint256 previousRound = currentRound;
        currentRound += 1;
        roundStartedAt = block.timestamp;
        roundAnswerHash[currentRound] = answerHash;

        emit NewRoundStarted(currentRound, previousRound, block.timestamp);
    }

    function mintReward(bytes calldata _proof) external {
        require(currentRound >= 1, "not started");
        require(!userWonRound[msg.sender][currentRound], "already won in the current round");

        require(verifier.verify(_proof, _buildPublicInputs()), "wrong proof");

        userWonRound[msg.sender][currentRound] = true;

        if (!roundHasWinner[currentRound]) {
            roundHasWinner[currentRound] = true;
            _mint(msg.sender, WINNER_NFT_ID, 1, "");
            emit WinnerOfRound(currentRound, msg.sender, WINNER_NFT_ID);
        } else {
            _mint(msg.sender, RUNNERUP_NFT_ID, 1, "");
            emit RunnerUpOfRound(currentRound, msg.sender, RUNNERUP_NFT_ID);
        }
    }

    /// @dev The circuit declares answer_hash as [u8; 32], so it occupies 32
    ///      separate public inputs, one byte each, right aligned in a bytes32.
    ///      proof_sender and round follow as single field elements.
    ///      Order here must match the parameter order in main().
    function _buildPublicInputs() internal view returns (bytes32[] memory) {
        bytes32 answerHash = roundAnswerHash[currentRound];

        bytes32[] memory input = new bytes32[](34);
        for (uint256 i = 0; i < 32; i++) {
            input[i] = bytes32(uint256(uint8(answerHash[i])));
        }
        input[32] = bytes32(uint256(uint160(msg.sender)));
        input[33] = bytes32(currentRound);

        return input;
    }

    /// @notice Convenience helper so a frontend can read the exact public
    ///         inputs it must prove against.
    function publicInputsFor(address player, uint256 round)
        external
        view
        returns (bytes32[] memory)
    {
        bytes32 answerHash = roundAnswerHash[round];

        bytes32[] memory input = new bytes32[](34);
        for (uint256 i = 0; i < 32; i++) {
            input[i] = bytes32(uint256(uint8(answerHash[i])));
        }
        input[32] = bytes32(uint256(uint160(player)));
        input[33] = bytes32(round);

        return input;
    }

    function uri(uint256 id) public pure override returns (string memory) {
        return string.concat(BASE_URI, Strings.toString(id), ".json");
    }
}
