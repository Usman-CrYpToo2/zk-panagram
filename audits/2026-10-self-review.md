# Self-Review: zk-panagram

| | |
|---|---|
| Date | October 2026 |
| Commit reviewed | [`5ad79f1`](https://github.com/Usman-CrYpToo2/zk-panagram/commit/5ad79f1) |
| Scope | [`src/main.nr`](../src/main.nr), [`contracts/src/panagram.sol`](../contracts/src/panagram.sol). The generated `verifier.sol` is out of scope. |
| Method | Manual review; circuit and contract test suites, including end-to-end verification of a real proof |

This is a self-review, not an independent audit. All findings are acknowledged; none required code changes to the circuit or contract.

## Summary

| Severity | Count |
|---|---|
| High | 1 |
| Medium | 1 |
| Low | 1 |
| Informational | 2 |

## Properties Verified

| Property | Evidence |
|---|---|
| The guess never appears in calldata | Private circuit input; only the proof is submitted |
| A proof is bound to one sender and one round | `proof_sender` and `round` are public inputs; `test_proofBoundToSender` |
| Circuit hashing matches `keccak256(abi.encodePacked(word))` | `test_matches_solidity_encodepacked`, `test_prefix_guess_fails`, `test_zero_padded_guess_fails` |
| Public input encoding matches the verifier | `test_publicInputsFromBbMatchContract` asserts all 34 inputs element by element |
| One winner per round, runner-up for later solvers, one mint per user per round | `WinnerOrder.t.sol` |

## Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| H-01 | High | Answer recoverable by offline search of the public hash | Acknowledged |
| M-01 | Medium | An unsolvable round halts the game permanently | Acknowledged |
| L-01 | Low | Verifier can be replaced at any time | Acknowledged |
| I-01 | Info | `eachRoundTime` is mutable storage without a setter | Acknowledged |
| I-02 | Info | Minting is not bounded by the round clock | Acknowledged, by design |

**H-01.** `startNewRound` publishes `keccak256(abi.encodePacked(word))` in the `roundAnswerHash` mapping. The input space of English words is around 2^18, so a dictionary search recovers the answer in under a second, after which an attacker can generate a valid proof and win without solving the puzzle. The proof hides the guess from calldata but cannot hide an answer whose hash is public. *Recommendation:* commit-reveal, which leaves the circuit unchanged. Design and trade-offs in [`docs/answer-secrecy.md`](../docs/answer-secrecy.md).

**M-01.** `startNewRound` requires the current round to have a winner. This is an intentional rule, documented by `test_unsolvedRoundBricksTheGame`. Its consequence is that any round that cannot be solved stops the game permanently. Beyond a word nobody guesses, this includes owner error: the circuit accepts guesses of at most 32 bytes (`MAX_WORD_LEN`), and the contract cannot check the length behind a hash, so starting a round with a longer word makes it unsolvable. *Recommendation:* validate the answer length off-chain before calling `startNewRound`, and consider an owner-only path to replace the answer of an unsolved round.

**L-01.** `setVerifier` lets the owner replace the verifier at any time, including during a round. A verifier that accepts every proof would let any address mint. *Recommendation:* make the verifier immutable, or apply a timelock and disallow changes during an active round.

**I-01.** `eachRoundTime` is a storage variable with no setter, so it is fixed at 10 minutes after deployment while costing a storage read. *Recommendation:* declare it `constant`, or add an `onlyOwner` setter.

**I-02.** `eachRoundTime` is a minimum time before the next round can start, not a minting deadline; players can mint for as long as the round remains current. This is intentional and documented by `test_mintingIsNotCappedByRoundClock`. Renaming the variable to `minRoundDuration` would make the behaviour clear from the code.
