use vodozemac::olm::{Account, OlmMessage, SessionConfig};

fn main() {
    let alice = Account::new();
    let mut bob = Account::new();

    bob.generate_one_time_keys(1);
    let bob_otk = *bob
        .one_time_keys()
        .values()
        .next()
        .expect("Bob must have one one-time key");

    let mut alice_session = alice
        .create_outbound_session(
            SessionConfig::version_1(),
            bob.curve25519_key(),
            bob_otk,
        )
        .expect("Alice creates outbound Olm session");

    bob.mark_keys_as_published();

    let first_plaintext = b"mesh-direct-prekey-message";
    let first = alice_session
        .encrypt(first_plaintext)
        .expect("Alice encrypts first message");

    let prekey = match first {
        OlmMessage::PreKey(message) => message,
        OlmMessage::Normal(_) => panic!("first outbound message must be PreKey"),
    };

    let first_wire = prekey.to_bytes();
    assert!(
        !first_wire
            .windows(first_plaintext.len())
            .any(|window| window == first_plaintext),
        "Olm pre-key wire unexpectedly contains plaintext"
    );

    let inbound = bob
        .create_inbound_session(
            SessionConfig::version_1(),
            alice.curve25519_key(),
            &prekey,
        )
        .expect("Bob creates inbound Olm session");

    let mut bob_session = inbound.session;
    assert_eq!(
        inbound.plaintext,
        first_plaintext,
        "Bob must recover first plaintext"
    );
    assert_eq!(
        alice_session.session_id(),
        bob_session.session_id(),
        "Olm session IDs must match"
    );

    let reply_plaintext = b"mesh-direct-reply";
    let reply = bob_session
        .encrypt(reply_plaintext)
        .expect("Bob encrypts reply");
    let reply_received = alice_session
        .decrypt(&reply)
        .expect("Alice decrypts Bob reply");
    assert_eq!(reply_received, reply_plaintext);

    let second_plaintext = b"mesh-direct-normal-ratchet-message";
    let second = alice_session
        .encrypt(second_plaintext)
        .expect("Alice encrypts ratcheted message");
    assert!(
        matches!(second, OlmMessage::Normal(_)),
        "after reply the session should produce a normal Olm message"
    );
    let second_received = bob_session
        .decrypt(&second)
        .expect("Bob decrypts ratcheted message");
    assert_eq!(second_received, second_plaintext);

    println!("M07_VODOZEMAC_DIRECT_PROBE_PASS");
    println!("M07_VODOZEMAC_ASYNC_PREKEY_PASS");
    println!("M07_VODOZEMAC_RATCHET_ROUNDTRIP_PASS");
}
