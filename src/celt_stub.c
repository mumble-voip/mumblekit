/* Copyright (C) 2012 Mikkel Krautz <mikkel@krautz.dk>

   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
   - Neither the name of the Mumble Developers nor the names of its
     contributors may be used to endorse or promote products derived from this
     software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <unistd.h>
#include <celt.h>

// This file contains stub functions for CELT
// When building in Opus mode for iOS, we get symbol clashes if we compile in both
// CELT 0.7.0 and Opus. Using these stubs, we can avoid a lot of ifdef madness.

int celt_encoder_ctl(CELTEncoder * st, int request, ...) {
	return 0;
}

CELTEncoder *celt_encoder_create(const CELTMode *mode, int channels, int *error) {
	return NULL;
}

CELTMode *celt_mode_create(celt_int32 Fs, int frame_size, int *error) {
	return NULL;
}

CELTDecoder *celt_decoder_create(const CELTMode *mode, int channels, int *error) {
	return NULL;
}

void celt_encoder_destroy(CELTEncoder *enc) {
	return;
}

void celt_decoder_destroy(CELTDecoder *dec) {
	return;
}

void celt_mode_destroy(CELTMode *mode) {
	return;
}

int celt_encode(CELTEncoder *st, const celt_int16 *pcm, celt_int16 *optional_synthesis, unsigned char *compressed, int nbCompressedBytes) {
    return 0;
}

int celt_decode_float(CELTDecoder *st, const unsigned char *data, int len, float *pcm) {
	return 0;
}
