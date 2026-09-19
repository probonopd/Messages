/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Force-included into the upstream iQuassel sources (see Engine/GNUmakefile).
 * Upstream was written against Apple's CoreFoundation for its big-endian
 * wire helpers; GNUstep systems need not have libs-corebase, and Foundation's
 * NSSwap* functions do the same job. */

#ifndef QUASSEL_COMPAT_H
#define QUASSEL_COMPAT_H

#import <Foundation/Foundation.h>

typedef uint16_t UInt16;

static inline uint32_t CFSwapInt32BigToHost(uint32_t v)
{
	return NSSwapBigIntToHost(v);
}

static inline uint32_t CFSwapInt32HostToBig(uint32_t v)
{
	return NSSwapHostIntToBig(v);
}

static inline uint16_t CFSwapInt16BigToHost(uint16_t v)
{
	return NSSwapBigShortToHost(v);
}

static inline uint16_t CFSwapInt16HostToBig(uint16_t v)
{
	return NSSwapHostShortToBig(v);
}

#endif
