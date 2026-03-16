/// Auth service — identity, biometrics, keypair management, and accounts.
///
/// Supports Nostr-style secp256k1 asymmetric identity where the public key
/// IS the user's identity. Platform implementations provide the concrete
/// behavior. Agents access this only through `AgentContext`.
library;

import 'dart:typed_data';

import 'package:kabuk/config/result.dart';

/// Abstract interface for authentication and identity management.
///
/// Manages keypair-based identity (Nostr-compatible secp256k1),
/// biometric authentication, and account linking across devices.
/// Supports multiple identities that can be switched at runtime.
abstract interface class AuthService {
  /// Get the current user's identity, or `null` if no keypair exists.
  Future<UserIdentity?> get currentUser;

  /// Whether a keypair has been generated or imported.
  Future<bool> get hasIdentity;

  /// Generate a new secp256k1 keypair.
  ///
  /// In multi-identity mode, this adds a new identity and switches to it.
  /// Returns the new identity.
  Future<UserIdentity> generateKeyPair();

  /// Import an existing identity from a Nostr-style nsec (bech32) string.
  ///
  /// Returns the identity derived from the imported private key.
  /// Returns [Failure] with [ValidationError] if the nsec is invalid.
  Future<Result<UserIdentity>> importFromNsec(String nsec);

  /// Export the private key as a Nostr-style nsec (bech32) string.
  ///
  /// Returns `null` if no keypair exists.
  Future<String?> exportNsec();

  /// Get the public key as a hex string.
  Future<String?> getPublicKeyHex();

  /// Get the public key as a Nostr-style npub (bech32) string.
  Future<String?> getNpub();

  /// Update the user's display name.
  Future<void> setDisplayName(String name);

  /// Authenticate using biometrics (fingerprint, face, etc.).
  Future<bool> authenticateBiometric({String? reason});

  /// Returns the raw 32-byte secp256k1 private key.
  ///
  /// Used for NIP-44 ECDH shared secret computation. Returns `null`
  /// if no keypair exists. Handle with care — this is the master secret.
  Future<Uint8List?> getPrivateKeyBytes();

  /// Sign arbitrary [data] using the user's secp256k1 private key
  /// with Schnorr signatures (BIP-340).
  ///
  /// The data is SHA-256 hashed before signing.
  /// Returns the 64-byte Schnorr signature wrapped in [Result].
  /// Returns [Failure] if no keypair exists.
  Future<Result<Uint8List>> sign(List<int> data);

  /// Sign a pre-hashed 32-byte message digest directly (no additional hashing).
  ///
  /// Used for Nostr NIP-01 event signing where the event ID is already
  /// the SHA-256 hash. The [hash] must be exactly 32 bytes.
  /// Returns the 64-byte Schnorr signature wrapped in [Result].
  /// Returns [Failure] if no keypair exists.
  Future<Result<Uint8List>> signHash(Uint8List hash);

  /// Verify a Schnorr [signature] against [data] using a [publicKey].
  ///
  /// The data is SHA-256 hashed before verification.
  /// The [publicKey] is the 32-byte x-only public key.
  Future<bool> verify(
    List<int> data,
    List<int> signature, {
    List<int>? publicKey,
  });

  /// Verify a Schnorr [signature] against a pre-hashed 32-byte [hash].
  ///
  /// Used for verifying Nostr event signatures where the event ID
  /// is already the SHA-256 hash.
  Future<bool> verifyHash(
    Uint8List hash,
    Uint8List signature, {
    Uint8List? publicKey,
  });

  // ---------------------------------------------------------------------------
  // Multi-identity management
  // ---------------------------------------------------------------------------

  /// Returns all stored identities.
  ///
  /// The list is ordered by creation time (oldest first). The active
  /// identity is the one returned by [currentUser].
  Future<List<UserIdentity>> listIdentities();

  /// Switches the active identity to the one with the given [publicKeyHex].
  ///
  /// Returns the switched-to identity, or [Failure] if no identity
  /// with that public key exists.
  Future<Result<UserIdentity>> switchIdentity(String publicKeyHex);

  /// Removes an identity by its [publicKeyHex].
  ///
  /// Cannot remove the last remaining identity. If the removed identity
  /// is the active one, the first remaining identity becomes active.
  /// Returns [Failure] if the identity does not exist or is the last one.
  Future<Result<void>> removeIdentity(String publicKeyHex);

  /// Export the private key as nsec for a specific identity.
  ///
  /// Returns `null` if the identity does not exist.
  Future<String?> exportNsecFor(String publicKeyHex);
}

/// Represents a user's cryptographic identity.
///
/// In the Nostr model, the public key IS the identity. The [npub]
/// is the human-friendly bech32 encoding of the public key.
class UserIdentity {
  /// Creates a [UserIdentity] with the given fields.
  const UserIdentity({
    required this.id,
    required this.displayName,
    this.publicKey,
    this.publicKeyHex,
    this.npub,
    this.createdAt,
  });

  /// Unique identifier — the hex-encoded public key.
  final String id;

  /// Human-readable display name.
  final String displayName;

  /// The 32-byte x-only public key.
  final Uint8List? publicKey;

  /// Hex-encoded public key string.
  final String? publicKeyHex;

  /// Nostr-style bech32-encoded public key (npub1...).
  final String? npub;

  /// When this identity was created.
  final DateTime? createdAt;

  /// Creates a copy with updated fields.
  UserIdentity copyWith({String? displayName, DateTime? createdAt}) {
    return UserIdentity(
      id: id,
      displayName: displayName ?? this.displayName,
      publicKey: publicKey,
      publicKeyHex: publicKeyHex,
      npub: npub,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
