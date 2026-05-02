import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SigningService {
  static const String _privateKeyKey = 'pharos_ed25519_private';
  static const String _publicKeyKey = 'pharos_ed25519_public';
  static const storage = FlutterSecureStorage();
  static final ed25519 = Ed25519();

  static Future<void> generateKeypair() async {
    final existingPrivate = await storage.read(key: _privateKeyKey);
    if (existingPrivate != null) {
      return; // Keys already exist
    }

    final keyPair = await ed25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    // Store keys as base64
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyBytes = publicKey.bytes;

    await storage.write(
      key: _privateKeyKey,
      value: base64Encode(privateKeyBytes),
    );
    await storage.write(
      key: _publicKeyKey,
      value: base64Encode(publicKeyBytes),
    );
  }

  static Future<String?> getPublicKeyBase64() async {
    return storage.read(key: _publicKeyKey);
  }

  static Future<String> signData(String data) async {
    final privateKeyB64 = await storage.read(key: _privateKeyKey);
    if (privateKeyB64 == null) {
      throw Exception('Private key not found. Call generateKeypair first.');
    }

    final privateKeyBytes = base64Decode(privateKeyB64);
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey([], type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

    final signature = await ed25519.sign(
      utf8.encode(data),
      keyPair: keyPair,
    );

    return base64Encode(signature.bytes);
  }
}
