// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Test} from "forge-std/Test.sol";
import {Panagram} from "../src/panagram.sol";
import {HonkVerifier, IVerifier} from "../src/verifier.sol";
import {console} from "forge-std/console.sol";

contract PanagramTest is Test {
    Panagram public panagram;
    HonkVerifier public verifier;

    // Must mirror Prover.toml exactly.
    bytes32 constant ANSWER_HASH = keccak256(abi.encodePacked("usman12"));
    address constant PROVER = 0x1234567890123456789012345678901234567890;

    bytes proof;
    bytes32[] publicInputs;

    function setUp() public {
        verifier = new HonkVerifier();
        panagram = new Panagram(address(verifier));

        proof = vm.readFileBinary("../out/proof");

        bytes memory raw = vm.readFileBinary("../out/public_inputs");
        uint256 n = raw.length / 32;
        publicInputs = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            bytes32 w;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                w := mload(add(add(raw, 0x20), mul(i, 0x20)))
            }
            publicInputs[i] = w;
        }
    }

    function test_publicInputsFromBbMatchContract() public {
        panagram.startNewRound(ANSWER_HASH);
        console.logBytes32(ANSWER_HASH);
        bytes32[] memory built = panagram.publicInputsFor(PROVER, 1);
        assertEq(built.length, publicInputs.length, "public input count");
        for (uint256 i = 0; i < built.length; i++) {
            assertEq(built[i], publicInputs[i], string.concat("mismatch at ", vm.toString(i)));
        }
    }

    function test_rawVerifierAcceptsProof() public view {
        assertTrue(verifier.verify(proof, publicInputs), "verifier rejected a valid proof");
    }

    function test_mintRewardWithRealProof() public {
        panagram.startNewRound(ANSWER_HASH);
        vm.prank(PROVER);
        panagram.mintReward(proof);
        assertEq(panagram.balanceOf(PROVER, panagram.WINNER_NFT_ID()), 1);
    }

    function test_proofBoundToSender() public {
        panagram.startNewRound(ANSWER_HASH);
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        panagram.mintReward(proof);
    }
}
