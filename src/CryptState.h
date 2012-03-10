// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#ifndef _CRYPTSTATE_H
#define _CRYPTSTATE_H

#include <openssl/aes.h>

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

        AES_KEY encrypt_key;
        AES_KEY decrypt_key;
        bool bInit;

    public:
        CryptState();

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
