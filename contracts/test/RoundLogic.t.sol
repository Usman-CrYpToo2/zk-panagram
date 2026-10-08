// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Test} from "forge-std/Test.sol";
import {Panagram} from "../src/panagram.sol";
import {IVerifier} from "../src/verifier.sol";

contract AlwaysTrueVerifier is IVerifier {
    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return true;
    }
}

contract RoundLogicTest is Test {
    Panagram panagram;

    function setUp() public {
        panagram = new Panagram(address(new AlwaysTrueVerifier()));
    }

    /// By design: a round cannot advance until it has a winner. Documents the consequence.
    function test_unsolvedRoundBricksTheGame() public {
        panagram.startNewRound(keccak256("word1"));
        vm.warp(block.timestamp + 365 days); // wait as long as you like
        vm.expectRevert(bytes("current round has no winner"));
        panagram.startNewRound(keccak256("word2"));
    }

    /// By design: eachRoundTime is a floor on the next round, not a mint deadline.
    function test_mintingIsNotCappedByRoundClock() public {
        panagram.startNewRound(keccak256("word1"));
        vm.warp(block.timestamp + 3650 days);
        vm.prank(address(0xA11CE));
        panagram.mintReward(hex"00"); // first solver of round 1, so correctly the winner
        assertEq(panagram.balanceOf(address(0xA11CE), 0), 1);
    }
}
