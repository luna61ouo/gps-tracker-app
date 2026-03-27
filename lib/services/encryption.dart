import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypts a GPS payload for gps-bridge using X25519 + AES-256-GCM.
///
/// Wire format matches gps-bridge's decrypt_payload() in crypto.py:
/// ```json
/// { "ephemeral_pub": "base64", "nonce": "base64", "ciphertext": "base64", "tag": "base64" }
/// ```
Future<Map<String, String>> encryptGpsPayload({
  required double lat,
  required double lng,
  required String timestamp,
  required String serverPubKeyB64,
  Map<String, dynamic> extraFields = const {},
}) async {
  // Decode server static public key
  final serverPubKeyBytes = base64.decode(serverPubKeyB64);
  final serverPublicKey = SimplePublicKey(
    serverPubKeyBytes,
    type: KeyPairType.x25519,
  );

  // Generate ephemeral keypair (forward secrecy per message)
  final x25519 = X25519();
  final ephemeralKeyPair = await x25519.newKeyPair();
  final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

  // ECDH shared secret
  final sharedSecretKey = await x25519.sharedSecretKey(
    keyPair: ephemeralKeyPair,
    remotePublicKey: serverPublicKey,
  );

  // HKDF-SHA256 → 32-byte AES key
  // salt = 32 zero bytes (matches Python cryptography's salt=None behaviour)
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final aesKey = await hkdf.deriveKey(
    secretKey: sharedSecretKey,
    nonce: Uint8List(32),
    info: utf8.encode('gps-bridge-v1'),
  );

  // AES-256-GCM encrypt
  final aesGcm = AesGcm.with256bits();
  final nonce = aesGcm.newNonce();
  final plaintext = utf8.encode(
    jsonEncode(<String, dynamic>{
      'v': 1,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      ...extraFields,
    }),
  );

  final secretBox = await aesGcm.encrypt(
    plaintext,
    secretKey: aesKey,
    nonce: nonce,
  );

  return {
    'ephemeral_pub': base64.encode(ephemeralPublicKey.bytes),
    'nonce': base64.encode(nonce),
    'ciphertext': base64.encode(secretBox.cipherText),
    'tag': base64.encode(secretBox.mac.bytes),
  };
}
