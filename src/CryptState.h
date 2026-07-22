// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#ifndef _CRYPTSTATE_H
#define _CRYPTSTATE_H

#include <CommonCrypto/CommonCryptor.h>
#include <stdint.h>
#include <stdbool.h>

#define AES_BLOCK_SIZE kCCBlockSizeAES128

namespace MumbleClient {

class CryptState {
    private:
        unsigned char raw_key[AES_BLOCK_SIZE];
        unsigned char encrypt_iv[AES_BLOCK_SIZE];
        unsigned char decrypt_iv[AES_BLOCK_SIZE];
        unsigned char decrypt_history[0x100];

        unsigned int uiGood;
        unsigned int uiLate;
        unsigned int uiLost;
        unsigned int uiResync;

        unsigned int uiRemoteGood;
        unsigned int uiRemoteLate;
        unsigned int uiRemoteLost;
        unsigned int uiRemoteResync;

        CCCryptorRef _encryptCryptor;
        CCCryptorRef _decryptCryptor;
        bool bInit;

    public:
        CryptState();
        ~CryptState();

        bool isValid() const;
        void genKey();
        void setKey(const unsigned char* rkey, const unsigned char* eiv, const unsigned char* div);
        void setDecryptIV(const unsigned char* iv);

        void ocb_encrypt(const unsigned char* plain, unsigned char* encrypted, unsigned int len, const unsigned char* nonce, unsigned char* tag);
        void ocb_decrypt(const unsigned char* encrypted, unsigned char* plain, unsigned int len, const unsigned char* nonce, unsigned char* tag);

        bool decrypt(const unsigned char* source, unsigned char* dst, unsigned int crypted_length);
        void encrypt(const unsigned char* source, unsigned char* dst, unsigned int plain_length);
};

}  // end namespace MumbleClient

#endif
