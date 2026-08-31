# Why the answer can be brute-forced, and how to actually fix it

A plain-English walkthrough. No prior crypto knowledge assumed.

---

## Part 1 — How your game works right now

Three actors: the **owner** (you), a **player**, and the **contract**.

**Step 1 — you start a round.**
You pick a word, say `"usman12"`. You do *not* put the word on-chain. You hash it first:

```
keccak256("usman12") = 0x68a1bc4b1e3840854c8e3acef1c765e277f3b8f39bcb01790f7d5dd6160f39a9
```

and call `startNewRound(0x68a1bc...)`. The contract saves it in `roundAnswerHash[1]`.

A hash is a **one-way fingerprint**. Easy to go forwards (word → hash). Supposedly impossible to go
backwards (hash → word). That "supposedly" is the whole story here — hold that thought.

**Step 2 — a player solves the puzzle.**
They figure out the word is `"usman12"`. Now they must prove it *without telling anyone*, because
transaction data is public — if they typed the word into the transaction, everyone watching the
mempool would copy it and mint too.

So they build a **ZK proof**. Think of it as a sealed certificate that says:

> "I know a word whose keccak256 equals `0x68a1bc...`, and I'm submitting from address `0xABC`,
> in round 1."

It proves all that **without containing the word**.

**Step 3 — the contract checks it.**
`mintReward(proof)` runs `verifier.verify(proof, publicInputs)`. The `publicInputs` are the facts the
proof is pinned to: the answer hash, the sender, and the round. If the proof is valid for exactly
those facts, the player mints. First solver gets the winner NFT, everyone after gets a runner-up.

**This part all works.** I tested it end-to-end with a real proof: the verifier accepts it, the NFT
mints, and a proof submitted from a *different* address is rejected. Your ZK layer is correct.

---

## Part 2 — So what's the problem?

Look at Step 1 again. `roundAnswerHash` is a **public** mapping, and your `startNewRound` transaction
is visible to everyone. So the answer hash is public knowledge the moment the round opens.

An attacker who never solves the puzzle can do this:

```
for every word in the dictionary:
    if keccak256(word) == 0x68a1bc...:
        found it
```

Hashing is one-way in the sense that you can't *reverse* the maths. But nobody needs to reverse it —
they just try every word and compare. **Guessing is not reversing.**

I actually ran this. Real dictionary, 235,764 words, secret word `"zymurgy"`:

```
Found 'zymurgy' after 235,756 tries in 19.8 seconds
```

And that was deliberately slow code (~12,000 hashes/sec). A proper keccak library does ~1,000,000
per second, so the real time is **under a quarter of a second**.

For a *panagram* it's even worse. You hand players the letters. So the attacker doesn't try 235,764
words — only the anagrams of those letters, usually a few hundred. Effectively instant.

### The root cause, stated precisely

> A hash is only as secret as the thing you hashed.

`keccak256` has 2^256 possible outputs — astronomically safe. But your **input** is an English word:
roughly 2^18 possibilities. The attacker searches the *input* space, not the output space. All the
strength of the hash is wasted, because the secret behind it is tiny.

This is why the same idea protects passwords poorly: `keccak256("password123")` is not safe, no
matter how strong keccak is.

---

## Part 3 — Why your salt idea doesn't work (as you proposed it)

Your proposal was: store `keccak(keccak(answer), salt)` and add the salt to the circuit.

A **salt** is a random extra value mixed into the hash. Good instinct — it's the standard tool. But
placing it inside the circuit breaks it. Here's why.

**The killer question: who needs to know the salt?**

If the circuit computes `keccak(keccak(guess), salt)`, then the salt is an *input to the circuit*.
Every honest player must run that circuit to make their proof. So **every player needs the salt.**

Players are the general public. So you'd have to publish the salt — in the frontend, in a contract
field, somewhere. And the moment it's public, the attacker reads it and runs:

```
for every word in the dictionary:
    if keccak(keccak(word), salt) == C:
        found it
```

Identical attack, one extra hash per guess. I measured it:

| Scheme | Attack result | Time |
|---|---|---|
| A — unsalted, `keccak(word)` | found `zymurgy` | 19.8 s |
| B — your proposal, salt **public** | found `zymurgy` | 39.7 s |

**Exactly 2× slower. That's all a public salt buys you.** In real terms: 0.2s becomes 0.4s.

And if you keep the salt secret instead? Then **no player can build a proof**, because they're
missing a required input. The game stops working entirely.

That's the trap: *inside the circuit, the salt must be public to be usable, and public makes it
useless.*

### What salts are actually for

A salt stops an attacker **precomputing one big table** and reusing it against many targets (and
stops identical inputs producing identical hashes). It does **not** stop someone attacking one
specific known target. That's the misconception. Your problem is the second kind.

---

## Part 4 — The insight that actually fixes it

Ask the killer question again, but about the *contract* instead of the circuit:

- Does the **player** need the salt? **No.** Their proof only needs `answer_hash = keccak(word)`,
  and they compute that from the word they solved. The salt never touches their side.
- Does the **contract** need the salt? Only at the moment it verifies.

So — keep the salt **out of the circuit** and **inside the contract**, and it can stay genuinely
secret, because nobody except you ever needs it.

Store this on-chain at round start:

```
C = keccak256(answerHash ‖ salt)      // salt = 32 random bytes, kept off-chain
```

Now what does an attacker see? Just `C`. To brute-force it they must guess **the word AND a
256-bit salt**. That's 2^256 possibilities — the same astronomical space that made keccak strong in
the first place. The dictionary attack is dead.

**The salt was the right idea. It just belongs in the contract, not the circuit.**

---

## Part 5 — The catch, and the scheme that handles it

There's a consequence. If the salt is secret, the contract **cannot verify a proof during the
round** — it can't rebuild `answerHash` from `C` without the salt.

So verification has to happen *later*. That gives us **commit–reveal**, in three phases:

### Phase 1 — Round starts
You store `C = keccak(answerHash ‖ salt)`. The salt stays on your machine.
**Nothing brute-forceable is public.** An attacker has nothing to grind.

### Phase 2 — Commit window (players race here)
A player solves the puzzle, builds their ZK proof exactly as they do today, and submits only a
**sealed envelope**:

```
commitment = keccak256(proof ‖ nonce)
```

The contract records the commitment and **the order they arrived in** — so winner vs runner-up is
still decided by who solved first. The answer is still nowhere on-chain.

An attacker can't cheat, because there's still nothing public to brute-force. And they can't wait
for the reveal, because by then the commit window has closed.

### Phase 3 — Reveal window
You publish `salt` and `answerHash`. The contract checks:

```
keccak256(answerHash ‖ salt) == C     // proves you didn't swap the answer afterwards
```

Then each player reveals their `proof + nonce`. The contract checks the envelope matches what they
committed, runs `verifier.verify(...)` — **the same call you have today** — and mints in commit
order.

### Why this genuinely works

By the time anything brute-forceable becomes public, the race is already over. Solving the word
offline no longer wins you anything, because you needed to commit *before* the information existed.

**And your circuit does not change at all.** `main.nr` stays exactly as it is. This is a
contract-side change — the opposite of where we were both originally looking.

### What it costs you

Being honest about the downsides:

- **Two transactions per player** instead of one, and a round has phases instead of being instant.
- **You must reveal.** If you go silent, nobody can mint. That collides with your rule that a round
  can't advance without a winner — together, a silent owner freezes the game permanently. This needs
  a decision (a deadline after which the round voids, or an emergency path).
- More storage, more code, more to get wrong.

---

## Part 6 — The simpler alternative: a signed voucher

If two phases feel too heavy, there's a one-transaction option.

Your backend already knows the word. Let it do the checking:

1. Player solves the puzzle and sends their proof to **your backend** (not the chain).
2. Backend verifies it and signs a message: *"address 0xABC may mint in round 1."*
3. Player calls `mintReward(proof, signature)`. The contract just checks the signature came from
   your known signer address.

**The answer hash never goes on-chain at all**, so there is nothing to brute-force. Problem solved,
one transaction, much less code.

**The cost:** you've introduced a trusted party. If your signing key leaks, anyone mints freely. If
your backend is down, nobody plays. For a project whose whole point is trustlessness, that's a real
concession — but it's a legitimate engineering choice, and plenty of production systems make it.

---

## Part 7 — Side by side

| | Today | Salt in circuit (your idea) | Commit–reveal | Signed voucher |
|---|---|---|---|---|
| Stops brute force | ❌ | ❌ (only 2× slower) | ✅ | ✅ |
| Circuit changes | — | Yes, big | **None** | None |
| Contract changes | — | Small | Large | Medium |
| Transactions per player | 1 | 1 | 2 | 1 |
| Trusted party | No | No | No | **Yes** |
| Owner must act after round | No | No | **Yes (reveal)** | Yes (sign) |

---

## Part 8 — How much does this actually matter?

Worth keeping in perspective before you spend days on it.

There's no prize pool and no money at stake — the reward is a cosmetic ERC1155. The "attack" is
winning a word game by grinding a wordlist instead of thinking. Nobody loses funds.

Also, the ZK layer is still doing real work today, and doing it correctly. It stops the *first*
solver from leaking the answer to the mempool, and it binds each proof to one sender and one round so
proofs can't be stolen or replayed. I verified both.

So this is best understood as **an inherent limitation of committing to a low-entropy secret in
public** — not a bug in your implementation. Fixing it is a legitimate upgrade, not an emergency.

**My honest recommendation:** if this is a learning or portfolio project, commit–reveal is the more
impressive and more correct answer, and it leaves your circuit untouched. If you mainly want it
shipped and simple, the signed voucher gets you there in far less code — just document the trust
assumption openly rather than hiding it.

---

## Quick glossary

- **Hash (keccak256)** — a one-way fingerprint. Easy forwards, infeasible to reverse *mathematically*
  — but trivially defeated by guessing when the input space is small.
- **Preimage** — the original input that produced a hash. Finding it by trying candidates is a
  "preimage attack."
- **Entropy** — how unpredictable a secret is. A dictionary word ≈ 2^18. A random 32-byte salt ≈
  2^256. Entropy of the *input* is what protects you, not strength of the hash.
- **Salt** — random data mixed into a hash. Blocks precomputed tables; does **not** block a targeted
  dictionary attack.
- **Public input** — a value a ZK proof is pinned to, visible to everyone. Yours: answer hash,
  sender, round.
- **Commit–reveal** — submit a sealed hash first, open it later, so nobody can react to information
  they shouldn't have had yet.
