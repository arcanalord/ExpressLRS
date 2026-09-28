use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;

fn credential(
    identity: &[u8],
    ciphersuite: Ciphersuite,
    provider: &OpenMlsRustCrypto,
) -> (CredentialWithKey, SignatureKeyPair) {
    let basic = BasicCredential::new(identity.to_vec());
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm())
        .expect("generate MLS signature key");
    signer
        .store(provider.storage())
        .expect("store MLS signature key");
    (
        CredentialWithKey {
            credential: basic.into(),
            signature_key: signer.to_public_vec().into(),
        },
        signer,
    )
}

fn main() {
    let ciphersuite =
        Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
    let alice_provider = OpenMlsRustCrypto::default();
    let bob_provider = OpenMlsRustCrypto::default();

    assert!(
        alice_provider
            .crypto()
            .supported_ciphersuites()
            .contains(&ciphersuite),
        "required X25519/Ed25519 MLS ciphersuite is not supported"
    );

    let (alice_credential, alice_signer) =
        credential(b"mm:alice", ciphersuite, &alice_provider);
    let (bob_credential, bob_signer) =
        credential(b"mm:bob", ciphersuite, &bob_provider);

    let bob_key_package = KeyPackage::builder()
        .build(
            ciphersuite,
            &bob_provider,
            &bob_signer,
            bob_credential,
        )
        .expect("build Bob key package");

    let mut alice_group = MlsGroup::new(
        &alice_provider,
        &alice_signer,
        &MlsGroupCreateConfig::default(),
        alice_credential,
    )
    .expect("create Alice MLS group");

    let (_commit, welcome_out, _group_info) = alice_group
        .add_members(
            &alice_provider,
            &alice_signer,
            core::slice::from_ref(bob_key_package.key_package()),
        )
        .expect("add Bob to MLS group");
    alice_group
        .merge_pending_commit(&alice_provider)
        .expect("merge Alice add-member commit");

    let serialized_welcome = welcome_out
        .tls_serialize_detached()
        .expect("serialize MLS Welcome");
    let welcome_in = MlsMessageIn::tls_deserialize(&mut serialized_welcome.as_slice())
        .expect("deserialize MLS Welcome");
    let welcome = match welcome_in.extract() {
        MlsMessageBodyIn::Welcome(welcome) => welcome,
        _ => panic!("expected MLS Welcome"),
    };

    let staged_bob = StagedWelcome::new_from_welcome(
        &bob_provider,
        &MlsGroupJoinConfig::default(),
        welcome,
        Some(alice_group.export_ratchet_tree().into()),
    )
    .expect("stage Bob join from Welcome");
    let mut bob_group = staged_bob
        .into_group(&bob_provider)
        .expect("create Bob MLS group");

    let secret = b"mesh-private-group-probe";
    let outbound = alice_group
        .create_message(&alice_provider, &alice_signer, secret)
        .expect("Alice creates encrypted MLS application message");
    let wire = outbound
        .to_bytes()
        .expect("serialize MLS application message");

    assert!(
        !wire.windows(secret.len()).any(|window| window == secret),
        "MLS wire unexpectedly contains plaintext"
    );

    let inbound = MlsMessageIn::tls_deserialize_exact(wire)
        .expect("deserialize MLS application message");
    let protocol_message = inbound
        .try_into_protocol_message()
        .expect("application message must be MLS protocol message");
    let processed = bob_group
        .process_message(&bob_provider, protocol_message)
        .expect("Bob processes MLS application message");

    match processed.into_content() {
        ProcessedMessageContent::ApplicationMessage(message) => {
            assert_eq!(message.into_bytes(), secret);
        }
        _ => panic!("expected MLS ApplicationMessage"),
    }

    println!("M07_OPENMLS_PROVIDER_PROBE_PASS");
    println!("M07_OPENMLS_TWO_MEMBER_LIFECYCLE_PASS");
}
