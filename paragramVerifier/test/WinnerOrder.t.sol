// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Test} from "forge-std/Test.sol";
import {Panagram} from "../src/panagram.sol";
import {IVerifier} from "../src/verifier.sol";

contract AlwaysTrueVerifier2 is IVerifier {
    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return true;
    }
}

contract WinnerOrderTest is Test {
    Panagram panagram;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    function setUp() public {
        panagram = new Panagram(address(new AlwaysTrueVerifier2()));
        panagram.startNewRound(keccak256("word1"));
    }

    function test_onlyFirstSolverGetsWinnerNft() public {
        vm.prank(alice);
        panagram.mintReward(hex"00");
        vm.prank(bob);
        panagram.mintReward(hex"00");
        vm.prank(carol);
        panagram.mintReward(hex"00");

        // id 0 = winner, id 1 = runner-up
        assertEq(panagram.balanceOf(alice, 0), 1, "alice should hold the winner NFT");
        assertEq(panagram.balanceOf(alice, 1), 0, "alice should hold no runner-up");
        assertEq(panagram.balanceOf(bob, 0), 0, "bob must NOT get a winner NFT");
        assertEq(panagram.balanceOf(bob, 1), 1, "bob should hold a runner-up");
        assertEq(panagram.balanceOf(carol, 0), 0, "carol must NOT get a winner NFT");
        assertEq(panagram.balanceOf(carol, 1), 1, "carol should hold a runner-up");
    }

    function test_winnerNftIsUniquePerRound_evenAcrossRounds() public {
        vm.prank(alice);
        panagram.mintReward(hex"00"); // round 1 winner

        vm.warp(block.timestamp + 11 minutes);
        panagram.startNewRound(keccak256("word2"));

        vm.prank(bob);
        panagram.mintReward(hex"00"); // round 2 winner

        assertEq(panagram.balanceOf(alice, 0), 1);
        assertEq(panagram.balanceOf(bob, 0), 1, "a new round mints a fresh winner NFT");
    }

    function test_sameUserCannotMintTwiceInOneRound() public {
        vm.startPrank(alice);
        panagram.mintReward(hex"00");
        vm.expectRevert(bytes("already won in the current round"));
        panagram.mintReward(hex"00");
        vm.stopPrank();
    }
}
