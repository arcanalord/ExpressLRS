package org.fpvclub.mesh

/**
 * Native M07 provider boundary.
 *
 * The current RC intentionally reports unavailable until the maintained
 * vodozemac Android backend is packaged and wired. Keeping this explicit
 * prevents release/private mode from silently falling back to plaintext or
 * to an ad-hoc crypto implementation.
 */
object M07NativeProviderRuntime {
    private const val PROVIDER_ID = "vodozemac-0.11"

    fun capabilities(): Map<String, Any?> = mapOf(
        "available" to false,
        "providerId" to PROVIDER_ID,
        "reason" to "M07_VODOZEMAC_NATIVE_BACKEND_NOT_PACKAGED",
        "suiteProfile" to mapOf(
            "identityAuthSuite" to "olm-curve25519-ed25519",
            "handshakeSuite" to "olm-v1-prekey",
            "ratchetSuite" to "olm-v1",
            "attachmentSuite" to "m07-attachment-v1",
            "transportPrivacySuite" to "m07-envelope-v1",
        ),
    )

    fun invoke(method: String, arguments: Any?): Any? {
        if (method == "capabilities") return capabilities()
        throw IllegalStateException(
            "M07_PROVIDER_UNAVAILABLE:$PROVIDER_ID:$method",
        )
    }
}
