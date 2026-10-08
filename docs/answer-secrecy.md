# Answer Secrecy

The zero-knowledge proof keeps a player's guess out of calldata. It does not keep the answer secret, because the answer's hash is public. This note describes the problem and two designs that address it.

## Problem

`startNewRound` stores `keccak256(abi.encodePacked(word))` in the public `roundAnswerHash` mapping. An attacker who has not solved the puzzle can hash candidate words offline and compare:

```
for word in dictionary:
    if keccak256(word) == roundAnswerHash[round]:
        return word
```

The strength of keccak256 lies in its 2^256 output space, but the search runs over the input space. An English dictionary holds roughly 2^18 words, and a single core computes on the order of 10^6 keccak hashes per second, so exhaustive search completes in well under a second. For a panagram the candidate set is narrower still, since the letters are given.

Once the word is known, the attacker generates a valid proof and calls `mintReward`, winning without solving the puzzle.

## Why a salt in the circuit is insufficient

Adding a salt as a public circuit input requires publishing it so the contract can rebuild the public inputs. A public salt does not enlarge the search space; it only adds one known value to each hash. Exhaustive search remains sub-second.

A salt is effective only if it stays secret until the race is over. That moves the fix from the circuit to the contract.

## Option A: commit-reveal

The circuit is unchanged.

| Phase | Owner | Player | Contract |
|---|---|---|---|
| Start | Publishes `C = keccak256(answerHash ‖ salt)`; keeps `salt` private | | Stores `C` |
| Commit | | Builds the proof as today; submits `keccak256(proof ‖ nonce)` | Records each commitment and its order |
| Reveal | Publishes `answerHash` and `salt` | Reveals `proof` and `nonce` | Checks `keccak256(answerHash ‖ salt) == C`, checks each commitment, runs `verify`, mints in commitment order |

Nothing searchable is public until the commit window closes, so solving offline after the reveal is too late.

Costs:

- Two transactions per player, and rounds become phased rather than instant.
- The owner must reveal. Combined with the rule that a round cannot advance without a winner, an owner who never reveals freezes the game. A reveal deadline after which the round is voided is required.
- Additional storage and logic.

## Option B: signed voucher

The answer hash never goes on-chain.

1. The player sends the proof to an off-chain service that knows the answer.
2. The service verifies the proof and signs `(player, round)`.
3. The player calls `mintReward(signature)`; the contract checks the signature against a known signer.

This is a single transaction with less contract code, but it introduces a trusted party. A leaked signing key allows unlimited minting, and a service outage halts play.

## Comparison

| | Current | Salt in circuit | Commit-reveal | Signed voucher |
|---|---|---|---|---|
| Prevents offline search | No | No | Yes | Yes |
| Circuit changes | | Yes | No | No |
| Contract changes | | Small | Large | Medium |
| Transactions per player | 1 | 1 | 2 | 1 |
| Trusted party | No | No | No | Yes |
| Owner action after round start | No | No | Reveal | Signing |

Commit-reveal is the recommended direction, as it preserves trustlessness.
