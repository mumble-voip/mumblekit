/* Copyright (C) 2010 Mikkel Krautz <mikkel@krautz.dk>

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

#ifndef __TIMEDELTA_H__
#define __TIMEDELTA_H__

#include <assert.h>
#include <sys/time.h>

#define TIMEDELTA_USEC_PER_SEC 1000000UL

typedef struct _TimeDelta {
    struct timeval tv1, tv2;
} TimeDelta;

static inline void
TimeDelta_start(TimeDelta *td)
{
    assert(gettimeofday(&td->tv1, NULL) == 0);
}

static inline void
TimeDelta_stop(TimeDelta *td)
{
    assert(gettimeofday(&td->tv2, NULL) == 0);
}

static inline unsigned long
TimeDelta_usec_delta(TimeDelta *td) {
    time_t sdt = td->tv2.tv_sec - td->tv1.tv_sec;
    // sdt > 0 means usec wrap around + (sdt-1)*USEC_PER_SEC
    unsigned long udt = 0;
    if (sdt > 0) {
        udt = (TIMEDELTA_USEC_PER_SEC - td->tv1.tv_usec) + td->tv2.tv_usec + (sdt-1) * TIMEDELTA_USEC_PER_SEC;
    } else {
        udt = td->tv2.tv_usec - td->tv1.tv_usec;
    }
    return udt;
}

#endif /* __TIMEDELTA_H__ */
