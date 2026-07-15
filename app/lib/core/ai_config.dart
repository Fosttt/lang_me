/// Compile-time AI server defaults, injected in CI via --dart-define from
/// GitHub Secrets (not stored in the repo). With these set, the app works
/// out of the box — no manual server setup; the values can still be
/// overridden in Settings.
const String kDefaultAiUrl = String.fromEnvironment('AI_URL');
const String kDefaultAiToken = String.fromEnvironment('AI_TOKEN');

/// SHA-256 of the server's self-signed certificate (DER, lowercase hex).
/// The HTTP client trusts ONLY this certificate — real TLS without a domain.
const String kAiCertSha256 = String.fromEnvironment('AI_CERT_SHA256');
