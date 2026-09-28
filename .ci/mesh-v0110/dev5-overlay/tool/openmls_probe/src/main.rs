use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider as _;

fn main() {
    let ciphersuite =
        Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
    let provider = OpenMlsRustCrypto::default();

    assert!(
        provider
            .crypto()
            .supported_ciphersuites()
            .contains(&ciphersuite),
        "required X25519/Ed25519 MLS ciphersuite is not supported"
    );

    let credential = BasicCredential::new(b"mm:probe".to_vec());
    let signer = SignatureKeyPair::new(ciphersuite.signature_algorithm())
        .expect("generate MLS signature key");
    signer
        .store(provider.storage())
        .expect("store MLS signature key");

    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: signer.to_public_vec().into(),
    };

    let key_package = KeyPackage::builder()
        .build(
            ciphersuite,
            &provider,
            &signer,
            credential_with_key,
        )
        .expect("build MLS key package");

    assert_eq!(
        key_package.key_package().ciphersuite(),
        ciphersuite,
        "key package suite mismatch"
    );

    println!("M07_OPENMLS_PROVIDER_PROBE_PASS");
}
