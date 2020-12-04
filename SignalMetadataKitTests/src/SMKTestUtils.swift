//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMetadataKit
import SignalClient

class MockCertificateValidator: NSObject, SMKCertificateValidator {

    public func throwswrapped_validate(senderCertificate: SenderCertificate, validationTime: UInt64) throws {
        // Do not throw
    }

    public func throwswrapped_validate(serverCertificate: ServerCertificate) throws {
        // Do not throw
    }
}

class MockClient: NSObject {

    var recipientUuid: UUID? {
        return address.uuid
    }

    var recipientE164: String? {
        return address.e164
    }

    let address: SMKAddress

    let deviceId: Int32
    let registrationId: Int32

    let identityKeyPair: IdentityKeyPair

    let sessionStore: InMemorySignalProtocolStore
    let preKeyStore: InMemorySignalProtocolStore
    let signedPreKeyStore: InMemorySignalProtocolStore
    let identityStore: InMemorySignalProtocolStore

    init(address: SMKAddress, deviceId: Int32, registrationId: Int32) {
        self.address = address
        self.deviceId = deviceId
        self.registrationId = registrationId
        self.identityKeyPair = IdentityKeyPair.generate()

        let protocolStore = InMemorySignalProtocolStore(identity: identityKeyPair,
                                                        deviceId: UInt32(bitPattern: deviceId))

        sessionStore = protocolStore
        preKeyStore = protocolStore
        signedPreKeyStore = protocolStore
        identityStore = protocolStore
    }

    func createSecretSessionCipher() throws -> SMKSecretSessionCipher {
        return try SMKSecretSessionCipher(sessionStore: sessionStore,
                                      preKeyStore: preKeyStore,
                                      signedPreKeyStore: signedPreKeyStore,
                                      identityStore: identityStore)
    }

    func generateMockPreKey() -> PreKeyRecord {
        let preKeyId = UInt32(Int32.random(in: 0...Int32.max))
        let preKey = try! PreKeyRecord(id: preKeyId, privateKey: PrivateKey.generate())
        try! self.preKeyStore.storePreKey(preKey, id: preKeyId, context: nil)
        return preKey
    }

    func generateMockSignedPreKey() -> SignedPreKeyRecord {
        let signedPreKeyId = UInt32(Int32.random(in: 0...Int32.max))
        let keyPair = IdentityKeyPair.generate()
        let generatedAt = Date()
        let identityKeyPair = try! self.identityStore.identityKeyPair(context: nil)
        let signature = identityKeyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())
        let signedPreKey = try! SignedPreKeyRecord(id: signedPreKeyId,
                                                   timestamp: UInt64(generatedAt.timeIntervalSince1970),
                                                   privateKey: keyPair.privateKey,
                                                   signature: signature)
        try! self.signedPreKeyStore.storeSignedPreKey(signedPreKey, id: signedPreKeyId, context: nil)
        return signedPreKey
    }

    // Moved from SMKSecretSessionCipherTest.
    // private void initializeSessions(TestInMemorySignalProtocolStore aliceStore, TestInMemorySignalProtocolStore bobStore)
    //     throws InvalidKeyException, UntrustedIdentityException
    func initializeSession(with bobMockClient: MockClient) {
        // ECKeyPair          bobPreKey       = Curve.generateKeyPair();
        let bobPreKey = bobMockClient.generateMockPreKey()

        // IdentityKeyPair    bobIdentityKey  = bobStore.getIdentityKeyPair();
        let bobIdentityKey = bobMockClient.identityKeyPair

        // SignedPreKeyRecord bobSignedPreKey = KeyHelper.generateSignedPreKey(bobIdentityKey, 2);
        let bobSignedPreKey = bobMockClient.generateMockSignedPreKey()

        // PreKeyBundle bobBundle             = new PreKeyBundle(1, 1, 1, bobPreKey.getPublicKey(), 2, bobSignedPreKey.getKeyPair().getPublicKey(), bobSignedPreKey.getSignature(), bobIdentityKey.getPublicKey());
        let bobBundle = try! SignalClient.PreKeyBundle(registrationId: UInt32(bitPattern: bobMockClient.registrationId),
                                                       deviceId: UInt32(bitPattern: bobMockClient.deviceId),
                                                       prekeyId: bobPreKey.id,
                                                       prekey: bobPreKey.publicKey,
                                                       signedPrekeyId: bobSignedPreKey.id,
                                                       signedPrekey: bobSignedPreKey.publicKey,
                                                       signedPrekeySignature: bobSignedPreKey.signature,
                                                       identity: bobIdentityKey.identityKey)

        // SessionBuilder aliceSessionBuilder = new SessionBuilder(aliceStore, new SignalProtocolAddress("+14152222222", 1));
        // aliceSessionBuilder.process(bobBundle);
        let bobProtocolAddress = try! ProtocolAddress(
            name: bobMockClient.address.uuid?.uuidString ?? bobMockClient.address.e164!,
            deviceId: UInt32(bitPattern: bobMockClient.deviceId))
        try! processPreKeyBundle(bobBundle,
                                 for: bobProtocolAddress,
                                 sessionStore: sessionStore,
                                 identityStore: identityStore,
                                 context: nil)

        // bobStore.storeSignedPreKey(2, bobSignedPreKey);
        // bobStore.storePreKey(1, new PreKeyRecord(1, bobPreKey));
        // NOTE: These stores are taken care of in the mocks' createKey() methods above.
    }

}
