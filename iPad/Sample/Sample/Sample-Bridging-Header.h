//
//  Sample-Bridging-Header.h
//  Sample
//
//  Created for libgnu.a testing
//

#ifndef Sample_Bridging_Header_h
#define Sample_Bridging_Header_h

// Define _GL_CONFIG_H_INCLUDED to bypass config.h requirement
// This is a simplified approach for testing libgnu.a functions
#ifndef _GL_CONFIG_H_INCLUDED
#define _GL_CONFIG_H_INCLUDED 1
#endif

// Include libgnu headers
#include "md5.h"

// timespec functions (from libgnu, uses stdckdint.h internally)
#include <time.h>
struct timespec timespec_add(struct timespec a, struct timespec b);
struct timespec timespec_sub(struct timespec a, struct timespec b);

#endif /* Sample_Bridging_Header_h */
