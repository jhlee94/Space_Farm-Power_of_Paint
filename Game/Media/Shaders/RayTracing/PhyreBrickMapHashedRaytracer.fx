/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/


// Enable ray hashing because we'll be tracing a subset of a mesh against the world
// The world will have different triangle indices so we'll need to compare hashes instead
#define HASH_TRIANGLES

// Offset the rays to avoid issues with planar geometry. This is a compromise betweeen quality and correctness.
// Too low - triangle edges will cause intersections.
// Too high - near objects won't occlude.
#define OFFSET_RAYS 0.0001f

#include "PhyreBrickMapRaytracer.fx"