use keccak256::keccak256;

global MAX_WORD_LEN: u32 = 32;

fn main(
    guess: BoundedVec<u8, MAX_WORD_LEN>, // private: the word, length carried inside
    answer_hash: pub [u8; 32],           // public: keccak256(abi.encodePacked(word))
    proof_sender: pub Field,             // public: msg.sender
    round: pub Field,                    // public: currentRound
) {
    // storage() is the 32 byte backing array, len() is how many bytes are real.
    // keccak only consumes the first len() bytes, so the zero tail is never
    // hashed. This matches keccak256(abi.encodePacked(word)) in Solidity.
    let computed = keccak256(guess.storage(), guess.len());
    
    assert(computed == answer_hash, "answer is not correct");
    // These are never compared against anything inside the circuit. Their job
    // is to be baked into the proof, so the contract's public inputs must
    // match them. That is what stops the proof being replayed from another
    // address or in a different round.
    assert(proof_sender == proof_sender);
    assert(round == round);
}

mod panagramtest {
    use super::{main, MAX_WORD_LEN};
    use keccak256::keccak256;
    use ethkey;
    use std::field;

    fn to_guess<let N: u32>(word: [u8; N]) -> BoundedVec<u8, MAX_WORD_LEN> {
        BoundedVec::from_array(word)
    }

    // Mirrors what the owner computes off-chain:
    // keccak256(abi.encodePacked(word))
    fn expected_hash<let N: u32>(word: [u8; N]) -> [u8; 32] {
        keccak256(word, N)
    }

    fn any_addr() -> Field {
        // Safety: test only, key generation is unconstrained
        unsafe { ethkey::PrivateKey::generate_private_key().public_key().to_address() }
    }

    // The anchor test. This hash was computed outside Noir for
    // keccak256(abi.encodePacked("usman12")). If this passes, the Noir side
    // and the Solidity side agree, and nothing else needs checking.
    #[test]
    fn test_matches_solidity_encodepacked() {
        let expected: [u8; 32] = [
            0x68, 0xa1, 0xbc, 0x4b, 0x1e, 0x38, 0x40, 0x85,
            0x4c, 0x8e, 0x3a, 0xce, 0xf1, 0xc7, 0x65, 0xe2,
            0x77, 0xf3, 0xb8, 0xf3, 0x9b, 0xcb, 0x01, 0x79,
            0x0f, 0x7d, 0x5d, 0xd6, 0x16, 0x0f, 0x39, 0xa9,
        ];
        let guess = to_guess("usman12".as_bytes());
        println(guess);

        main(guess, expected, any_addr(), 1);
    }

    #[test]
    fn test_correct_guess_passes() {
        let answer_hash = expected_hash("usman12".as_bytes());
        let guess = to_guess("usman12".as_bytes());

        main(guess, answer_hash, any_addr(), 1);
    }

    #[test(should_fail_with = "answer is not correct")]
    fn test_wrong_guess_fails() {
        let answer_hash = expected_hash("usman12".as_bytes());
        let guess = to_guess("wrongword".as_bytes());

        main(guess, answer_hash, any_addr(), 1);
    }

    // A prefix of the answer must fail. This is the canary for the length
    // actually reaching keccak. If it passes, the length is being ignored.
    #[test(should_fail_with = "answer is not correct")]
    fn test_prefix_guess_fails() {
        let answer_hash = expected_hash("usman12".as_bytes());
        let guess = to_guess("usman".as_bytes());

        main(guess, answer_hash, any_addr(), 1);
    }

    // The same word right padded to 32 bytes, with all 32 counted as real.
    // This is the "option B" encoding and must NOT match option A.
    #[test(should_fail_with = "answer is not correct")]
    fn test_zero_padded_guess_fails() {
        let answer_hash = expected_hash("usman12".as_bytes());

        let word = "usman12".as_bytes();
        let mut padded: [u8; 32] = [0; 32];
        for i in 0..word.len() {
            padded[i] = word[i];
        }
        let guess = to_guess(padded);

        main(guess, answer_hash, any_addr(), 1);
    }

    #[test(should_fail_with = "answer is not correct")]
    fn test_empty_guess_fails() {
        let answer_hash = expected_hash("usman12".as_bytes());
        let guess: BoundedVec<u8, MAX_WORD_LEN> = BoundedVec::new();

        main(guess, answer_hash, any_addr(), 1);
    }

    // Capacity boundary. Guards against an off by one at the maximum length.
    #[test]
    fn test_max_length_word_passes() {
        let word: [u8; 32] = [65; 32]; // 32 copies of "A"
        let answer_hash = expected_hash(word);
        let guess = to_guess(word);

        main(guess, answer_hash, any_addr(), 1);
    }

    #[test]
    fn test44() {
         let input = "usman12".as_bytes();
         let a = keccak256(input, input.len());
         let b = field::bytes32_to_field(a);
         println(b);
    }
}