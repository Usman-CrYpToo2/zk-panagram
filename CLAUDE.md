# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A zk word-guessing game ("panagram") in two halves that must stay in lockstep:

- **`src/main.nr`** — Noir circuit, package `zkpanagram` (nargo 1.0.0-beta.21). Proves *"I know a word whose keccak256 equals this round's answer hash"* without revealing the word.
- **`contracts/`** — Foundry project. `src/panagram.sol` is an ERC1155 that mints a winner NFT (id 0) to the first correct prover in a round and a runner-up NFT (id 1) to everyone after. `src/verifier.sol` is the **generated** Barretenberg ZK-Honk verifier — never hand-edit it, regenerate it.


## Commands

Circuit (repo root):

```bash
ethkey test                     # all circuit tests (mod panagramtest in main.nr)
ethkey test test_prefix_guess   # single test; the arg is a substring filter on the name
nargo compile                   # -> target/zkpanagram.json
nargo execute                   # witness from Prover.toml -> target/zkpanagram.gz
```

**Use `ethkey test`, not `nargo test`.** The tests call `ethkey::PrivateKey::generate_private_key()`,
which needs the ethkey oracle server; under plain `nargo test` all 7 fail with
`0 output values were provided as a foreign call result`. `ethkey test` starts and tears down that
server for you. (`ethkey check` type-checks; `ethkey server` runs the oracle in the foreground.)

Proof + verifier generation (bb 5.0.0-nightly). `--oracle_hash keccak` is required for on-chain verification, and the vk must be regenerated before the verifier:

```bash
bb write_vk -b target/zkpanagram.json -o out --oracle_hash keccak
bb prove    -b target/zkpanagram.json -w target/zkpanagram.gz -k out/vk -o out --oracle_hash keccak
bb write_solidity_verifier -k out/vk -o contracts/src/verifier.sol
```

`-k out/vk` on `prove` is not optional: without it bb looks for `./target/vk` and dies with
`Unable to open file: ./target/vk` **after** printing a normal-looking progress line, leaving a stale
`out/proof` in place. A proof only verifies against the vk it was produced with — if `out/proof` is
older than `out/vk`, re-prove.

`out/` holds the last run: `proof` (8768 bytes), `public_inputs` (1088 = 34x32), `vk`, `vk_hash`.

Contracts (`cd contracts`):

```bash
forge build
forge test -vvv
forge test --match-test <name> -vvv
forge fmt --check                    # CI enforces this
```

CI (`.github/workflows/ci.yml`) runs the circuit tests through `ethkey test`, then `forge build` and `forge test` in `contracts/`.

## The circuit ↔ contract interface (the thing that breaks)

`main()` is `(guess: private BoundedVec<u8,32>, answer_hash: pub [u8;32], proof_sender: pub Field, round: pub Field)`.

Because `answer_hash` is a byte array it flattens to **32 separate public inputs, one byte each right-aligned in a bytes32**, then sender, then round — **34 values, in that exact order**. `Panagram._buildPublicInputs()` reconstructs precisely that. Reordering or retyping `main()`'s parameters silently breaks verification with no compile error on either side.

The generated verifier reports `NUMBER_OF_PUBLIC_INPUTS = 42`; that is 34 plus `PAIRING_POINTS_SIZE = 8`. `HonkVerifier.verify()` requires `publicInputs.length == publicInputsSize - PAIRING_POINTS_SIZE`, i.e. the 34 the contract passes. When the circuit's public inputs change, the new count is `NUMBER_OF_PUBLIC_INPUTS - 8`, and both `_buildPublicInputs()` and `publicInputsFor()` must be updated to match.

`proof_sender` and `round` are deliberately unconstrained inside the circuit (`assert(x == x)`). They exist only to be baked into the public inputs so the contract can bind a proof to one `msg.sender` and one round — that is the entire replay defense. Do not "clean up" those asserts.

Hashing must stay `keccak256(guess.storage(), guess.len())` so it matches `keccak256(abi.encodePacked(word))` in Solidity — the BoundedVec's zero tail is never hashed. `test_prefix_guess_fails` and `test_zero_padded_guess_fails` are the canaries; if either starts passing, the length stopped reaching keccak.

After changing `main.nr`, the full chain must be rerun (`nargo compile` → `bb write_vk` → `bb write_solidity_verifier`), otherwise `VK_HASH` in `verifier.sol` drifts from `out/vk_hash` and every proof is rejected.

`test/Panagram.t.sol` pins this down end-to-end: it loads `out/proof` and `out/public_inputs` and
asserts bb's 34 public inputs equal `publicInputsFor()` element by element, that `HonkVerifier`
accepts the proof, that `mintReward` mints the winner NFT, and that a different `msg.sender` is
rejected. Run it after any change to `main.nr` or the encoding. It needs
`fs_permissions = [{ access = "read", path = "../out" }]` in `foundry.toml` to read `out/`.

## Intentional design decisions (do not "fix" these)

- **A round cannot advance without a winner.** `startNewRound` requires
  `roundHasWinner[currentRound]`, deliberately: every round must be solved before the next begins.
  A word nobody guesses stalls the game until someone solves it. This is by design — do not add a
  timeout escape without asking. `test_unsolvedRoundBricksTheGame` documents the behavior.
- **`eachRoundTime` is a minimum round length, not an expiry.** `startNewRound` checks
  `block.timestamp - roundStartedAt > eachRoundTime`, i.e. a floor on how soon the *next* round may
  start. It deliberately does not cap minting: players can still mint after 10 minutes, and the round
  ends when the owner starts the next one, not when the clock runs out. The name reads like an expiry
  but the code is a floor — read it as `minRoundDuration`.

## Known issues

- **The answer hash is unsalted and public** (see `docs/answer-secrecy.md` and `audits/`). `roundAnswerHash` is a public mapping and
  `startNewRound`'s calldata is visible, so anyone can dictionary-attack `keccak256(word)` offline
  and win without solving the puzzle. A salted commitment would fix it; the current scheme only
  hides the word from calldata, not from the chain.
- `eachRoundTime` is non-constant but has no setter, so the 10-minute floor can never be changed
  after deployment. Either add an `onlyOwner` setter or make it `constant`.
- `forge fmt --check` fails on `src/panagram.sol` and the generated `src/verifier.sol`, so CI does not run it. Exclude `verifier.sol` from formatting before enabling the check; it is overwritten on every regeneration.
- There is no deploy script.
- `println(proof_sender)` in `main.nr` is leftover debug output and should be removed.
- `Prover.toml` is pinned to the demo answer `"usman12"` (hash `0x68a1bc4b...`) with
  `proof_sender = 0x1234...7890` and `round = 1`. Real proving substitutes the player address and
  current round.
