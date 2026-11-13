import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoService {
  final _x25519 = X25519();
  final _aes = AesGcm.with256bits();

  Future<SimpleKeyPair> generateKeyPair() async {
    return _x25519.newKeyPair();
  }

  Future<String> publicKeyToBase64(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<String> privateKeyToBase64(SimpleKeyPair keyPair) async {
    return base64Encode(await keyPair.extractPrivateKeyBytes());
  }

  Future<SimpleKeyPair> keyPairFromPrivateKey(String privateKey) {
    return _x25519.newKeyPairFromSeed(base64Decode(privateKey));
  }

  Future<List<int>> deriveChatKey(
    String chatId,
    String peerPublicKey,
    SimpleKeyPair ownKeyPair,
  ) async {
    final peerBytes = base64Decode(peerPublicKey);
    final peerKey = SimplePublicKey(peerBytes, type: KeyPairType.x25519);
    final secret = await _x25519.sharedSecretKey(
      keyPair: ownKeyPair,
      remotePublicKey: peerKey,
    );
    final keyMaterial = await secret.extractBytes();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(keyMaterial),
      nonce: utf8.encode('community-chat-v1'),
      info: utf8.encode(chatId),
    );
    return (await derived.extractBytes()).toList();
  }

  Future<String> encryptText(
    String plaintext,
    String chatId,
    String senderUserId,
    List<int> key, {
    String type = 'text',
  }) async {
    final encrypted = await encryptBytes(
      utf8.encode(plaintext),
      chatId,
      senderUserId,
      key,
      type: type,
    );
    return 'enc1:${base64Encode(encrypted)}';
  }

  Future<Uint8List> encryptBytes(
    List<int> plaintext,
    String chatId,
    String senderUserId,
    List<int> key, {
    required String type,
  }) async {
    final nonce = _randomBytes(12);
    final aad = utf8.encode('$chatId|$senderUserId|$type');
    final secretKey = SecretKey(key);
    final secretBox = await _aes.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );
    final combined = <int>[
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return Uint8List.fromList(combined);
  }

  Future<Map<String, dynamic>> decryptText(
    String payload,
    String chatId,
    String senderUserId,
    List<int> key, {
    String type = 'text',
  }) async {
    try {
      if (!payload.startsWith('enc1:')) {
        return {'ok': true, 'text': payload};
      }
      final bytes = base64Decode(payload.substring('enc1:'.length));
      final plain = await decryptBytes(
        bytes,
        chatId,
        senderUserId,
        key,
        type: type,
      );
      return {'ok': true, 'text': utf8.decode(plain)};
    } catch (_) {
      return {'ok': false, 'text': '🔒 This message can\'t be opened'};
    }
  }

  Future<Uint8List> decryptBytes(
    List<int> encrypted,
    String chatId,
    String senderUserId,
    List<int> key, {
    required String type,
  }) async {
    if (encrypted.length < 28) {
      throw const FormatException('Encrypted message is too short.');
    }
    final nonce = encrypted.sublist(0, 12);
    final ciphertext = encrypted.sublist(12, encrypted.length - 16);
    final tag = encrypted.sublist(encrypted.length - 16);
    final plaintext = await _aes.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
      secretKey: SecretKey(key),
      aad: utf8.encode('$chatId|$senderUserId|$type'),
    );
    return Uint8List.fromList(plaintext);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
