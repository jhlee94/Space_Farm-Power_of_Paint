/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Based on Scalable Ambient Obscurance reference implementation at
// http://graphics.cs.williams.edu/papers/SAOHPG12
//
// Sony Interactive Entertainment Inc made changes.
// (C) Copyright 2016 Sony Interactive Entertainment Inc.
// 
// License information for the original code:
//===========================================

/**
 \author Morgan McGuire and Michael Mara, NVIDIA Research

 Reference implementation of the Scalable Ambient Obscurance (SAO) screen-space ambient obscurance algorithm. 
 
 The optimized algorithmic structure of SAO was published in McGuire, Mara, and Luebke, Scalable Ambient Obscurance,
 <i>HPG</i> 2012, and was developed at NVIDIA with support from Louis Bavoil.

 The mathematical ideas of AlchemyAO were first described in McGuire, Osman, Bukowski, and Hennessy, The 
 Alchemy Screen-Space Ambient Obscurance Algorithm, <i>HPG</i> 2011 and were developed at 
 Vicarious Visions.  
 
 DX11 HLSL port by Leonardo Zide of Treyarch

 <hr>

  Open Source under the "BSD" license: http://www.opensource.org/licenses/bsd-license.php

  Copyright (c) 2011-2012, NVIDIA
  All rights reserved.

  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

// Generate the base mip map of the linear depth texture using compute.
[numthreads(8, 8, 1)]
void GenerateLinearDepth_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint x = DispatchThreadId.x;
	uint y = DispatchThreadId.y;

	float depth = DepthBuffer.Load(int3(x,y,0));
	float linearDepth = (cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));

	RWLinearDepthBuffer[int2(x,y)] = -linearDepth;
}

// The previous mip map Level
unsigned int prevMipMapLevel;
// Downsample the linear depth texture to create mipmaps.
void DownSampleDepth(FullScreenVS_Output2 input) 
{
    int2 pos = int2(input.Pos.xy);

#ifdef __ORBIS__
	RWLinearDepthBuffer.MipMaps(prevMipMapLevel+1, pos) = RWLinearDepthBuffer.MipMaps(prevMipMapLevel, pos * 2 + int2((pos.y & 1), (pos.x & 1)));
#endif
}

// Reconstruct the view position from the depth value.
float3 getViewPosition(int2 pos, float2 tex) 
{
	float depth = LinearDepthBuffer.Load(int3(pos, 0)).r;
	float2 viewPos = tex * depth;

#ifndef __ORBIS__
	viewPos.y *=-1;
#endif
	
	return float3(viewPos,-depth);
}

// Used for packing float Z into the 2x8bit GB channels
float CSZToKey(float z) {
	return clamp(-z * (1.0 / cameraNearFar.y), 0.0, 1.0);  
}

// Used for packing float Z into the 2x8bit GB channels 
void packKey(float key, out float2 p) {
	// Round to the nearest 1/256.0
	float temp = floor(key * 256.0);

	// Integer part
	p.x = temp * (1.0 / 256.0);

	// Fractional part
	p.y = key * 256.0 - temp;
}

// A 11 tap sized sample kernel.
#define kernelSize1 (11)

// Taps around the circle that the spiral pattern makes
float2 tapLocation(int sampleNumber, float spinAngle, out float ssR)
{
	// Radius relative to ssR
	float alpha = float(sampleNumber + 0.5) * (1.0 / kernelSize1);
	float angle = alpha * (7 * 6.28) + spinAngle;  // 7 spiral turns;

	ssR = alpha;
	return float2(cos(angle), sin(angle));
}

// If using depth mip levels, the log of the maximum pixel offset before we need to switch to a lower 
// miplevel to maintain reasonable spatial locality in the cache
// If this number is too small (< 3), too many taps will land in the same pixel, and we'll get bad variance that manifests as flashing.
// If it is too high (> 5), we'll get bad performance because we're not using the MIP levels effectively
#define LOG_MAX_OFFSET 3

// Max mip level (Not set on D3D atm).
int maxMip;

float3 getOffsetPosition(int2 ssC, float2 unitOffset, float ssR) 
{
	// Derivation:
	//  mipLevel = floor(log(ssR / MAX_OFFSET));
	int mipLevel = clamp((int)floor(log2(ssR)) - LOG_MAX_OFFSET, 0, maxMip);

#ifndef __ORBIS__
	mipLevel = 0; // At the moment our d3d implementation does not support mipmaps.
#endif

	int2 ssP = int2(ssR*unitOffset) + ssC;

	float3 P;
	P.z = LinearDepthBuffer.Load(int3(ssP >> mipLevel, mipLevel)).r;

	float2 tex = float2(ssP) + float2(0.5, 0.5);
	tex = tex *InvProjXY.zw - InvProjXY.xy;
	P.xy = tex * P.z;

#ifndef __ORBIS__
	P.y *=-1;
#endif
	
	return float3(P.xy,-P.z);
}

// The sao sample radius.
float uRadius;

// Bias to avoid AO in smooth corners.
float depthBias = 0.01;

// Sample for offset location and calucate occlusion contribution depending on difference between center and sample point.
float sampleAO(int2 ssC, float3 C, float3 n_C, float ssDiskRadius, int tapIndex, float randomPatternRotationAngle) 
{
	// Offset on the unit disk, spun for this pixel
	float ssR;
	float2 unitOffset = tapLocation(tapIndex, randomPatternRotationAngle, ssR);
	ssR *= ssDiskRadius;

	// The occluding point in camera space
	float3 Q = getOffsetPosition(ssC, unitOffset, ssR);

	float3 v = Q - C;

	float vv = dot(v, v);
	float vn = dot(v, n_C);

    const float epsilon = 0.01;
    float f = max(uRadius*uRadius - vv, 0.0);
	return f * f * f * max((vn - depthBias) / (epsilon + vv), 0.0);  
}

float random( float2 p )
{
      // recalculate the uv's 
      p = ((p/InvProjXY.xy) +1.0f)/2.0f;

      // http://stackoverflow.com/questions/12964279/whats-the-origin-of-this-glsl-rand-one-liner
      return frac(sin(dot(p ,float2(12.9898,78.233))) * 43758.5453);
}

// Calculate the actual SAO value and stor linear float z value in xy channel.
float4 getSAO(float3 viewPos, float3 viewNormal, int2 pixel, float rand)
{
	float projScale = 500.0f; // aproxximation.
	float intensity = 1.0f;

	float4 outColor;

	packKey(CSZToKey(viewPos.z), outColor.gb);

	// Hash function used in the HPG12 AlchemyAO paper
	float randomPatternRotationAngle = rand * 2 * 3.14159f;//(3 * pixel.x ^ pixel.y + pixel.x * pixel.y) * 10;

	// Choose the screen-space sample radius
	// proportional to the projected area of the sphere
	float ssDiskRadius =  -projScale * uRadius / viewPos.z;
	
	float sum = 0.0;
	for (unsigned int i = 0; i < kernelSize1; ++i)  
		sum += sampleAO(pixel, viewPos, viewNormal, ssDiskRadius, i, randomPatternRotationAngle);
	
    float temp = uRadius * uRadius * uRadius; 
    sum /= temp * temp; 
	float A = max(0.0, 1.0 - sum * intensity * (5.0 / kernelSize1)); 

	// Bilateral box-filter over a quad for free, respecting depth edges
	// (the difference that this makes is subtle)
	if (abs(ddx(viewPos.z)) < 0.02) 
	{
		A -= ddx(A) * ((pixel.x & 1) - 0.5);
	}
	if (abs(ddy(viewPos.z)) < 0.02) 
	{
		A -= ddy(A) * ((pixel.y & 1) - 0.5);
	}

	outColor.r = A;
	outColor.w = 1.0;

	return outColor;
}

// SAO shader where normals are getting recalculated from linear depth buffer.
float4 generateSAO(FullScreenVS_Output3 input) : FRAG_OUTPUT_COLOR
{
	// Pixel being shaded 
	int2 pixel = int2(input.Pos.xy);

	// World space point being shaded
	float3 viewPos = getViewPosition(pixel, input.Tex);
#ifndef __ORBIS__
	float3 viewNormal = normalize(cross(ddy(viewPos), ddx(viewPos)));
#else
	float3 viewNormal = normalize(cross(ddx(viewPos), ddy(viewPos)));
#endif
	float rand = random(input.Tex);
	return getSAO(viewPos, viewNormal, pixel, rand);
}

// SAO shader where view normals are supplied in a texture.
float4 generateSAOWithNormalBuffer(FullScreenVS_Output3 input) : FRAG_OUTPUT_COLOR
{
		// Pixel being shaded 
	int2 pixel = int2(input.Pos.xy);

	// World space point being shaded
	float3 viewPos = getViewPosition(pixel, input.Tex);

	float4 normalMapValue = (NormalBuffer.Load(int3(pixel,0))).xyzw;
	float3 viewNormal;
	if (normalMapValue.w != 1.0f)
	{
		 viewNormal = normalMapValue.xyz*2 - 1;
	} else
		 viewNormal = float3(0,0,1);

	float rand = random(input.Tex);
	return getSAO(viewPos, viewNormal.xyz, pixel, rand);
}

// Paramter to tune the influence of the depth values for the bilateral filter.
float edgeSharpness;

//  Step in 2-pixel intervals since we already blurred against neighbors in the
//  first AO pass.  This constant can be increased while R decreases to improve
//  performance at the expense of some dithering artifacts. 
    
//  Morgan found that a scale of 3 left a 1-pixel checkerboard grid that was
//  unobjectionable after shading was applied but eliminated most temporal incoherence
//  from using small numbers of sample taps.
#define SCALE               (2)

/** Filter radius in pixels. This will be multiplied by SCALE. */
#define R                   (3)

// Gaussian coefficients
static const float gaussian[] = 
	{ 0.356642, 0.239400, 0.072410, 0.009869 };
//	{ 0.398943, 0.241971, 0.053991, 0.004432, 0.000134 };  // stddev = 1.0
//	{ 0.153170, 0.144893, 0.122649, 0.092902, 0.062970 };  // stddev = 2.0
//	{ 0.111220, 0.107798, 0.098151, 0.083953, 0.067458, 0.050920, 0.036108 }; // stddev = 3.0

// Either (1, 0) or (0, 1) for the x or y filter pass.
float4 blurAxis;

// Unpacks the view space depth from x and y channel. 
// Returns a number on (0, 1)
float unpackKey(float2 p)
{
	return p.x * (256.0 / 257.0) + p.y * (1.0 / 257.0);
}

// Billateral blur  shader.
float4 blur(FullScreenVS_Output2 input) : FRAG_OUTPUT_COLOR
{
    int2 centerPixel = int2(input.Pos.xy);

	float4 color = float4(1,1,1,1);
	float4 temp = BlurBuffer.Load(int3(centerPixel, 0));

	color.gb = temp.gb;
	float key = unpackKey(color.gb);

	float sum = temp.r;

	if (key == 1.0) 
	{ 
		// Sky pixel (if you aren't using depth keying, disable this test)
		color.r = sum;
		return color;
	}

	// Base weight for depth falloff.  Increase this for more blurriness,
	// decrease it for better edge discrimination
	float baseTap = gaussian[0];
	float totalWeight = baseTap;
	sum *= totalWeight;

	[unroll]
	for (int r = -R; r <= R; ++r) 
	{
		// We already handled the zero case above.  This loop should be unrolled and the branch discarded
		if (r != 0) 
		{
			temp = BlurBuffer.Load(int3(centerPixel + blurAxis.xy * (r * SCALE), 0));
			float tapKey = unpackKey(temp.gb);
			float value  = temp.r;

			// spatial domain: offset gaussian tap
			float weight = 0.3 + gaussian[abs(r)];

			// range domain (the "bilateral" weight). As depth difference increases, decrease weight.
			weight *= max(0.0, 1.0 - (2000.0 * edgeSharpness) * abs(tapKey - key));

			sum += value * weight;
			totalWeight += weight;
		}
	}

	const float epsilon = 0.0001; // Avoid divide by 0.
	color.r = sum / (totalWeight + epsilon);	

	return color;
}
