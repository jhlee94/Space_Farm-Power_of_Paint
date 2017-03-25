/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

//! Defining context switches
bool PhyreContextSwitches
<
	string ContextSwitchNames[] = { "DEBUG_TEMPORAL", "ORTHO_CAMERA", "USE_CLIPPING", "USE_SHARPENING", "USE_VARIANCE_CLIPPING", "USE_YCOCG", "SHOW_CLIPPED", "SHOW_DISOCCLUDED" };
>;
#define DEFINED_CONTEXT_SWITCHES

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Shader parameters.

Texture2D	ColorBuffer;						// The input color buffer.
Texture2D	DepthBuffer;						// The input depth buffer.
Texture2D	HistoryBuffer;						// The history buffer for temporal reprojection.
Texture2D	VelocityBuffer;						// The buffer for the per-pixel motion vectors.
Texture2D	PreviousColorBuffer;				// The previous color buffer for temporal filtering.
Texture2D	PreviousVelocityBuffer1;			// The previous velocity buffer for the N-1 frame.
Texture2D	PreviousVelocityBuffer2;			// The previous velocity buffer for the N-2 frame.
Texture2D	PreviousVelocityBuffer3;			// The previous velocity buffer for the N-3 frame.
Texture2D	DebugBuffer;						// The buffer for storing the debug visualizations.

float		Gamma;								// The gamma factor for tweaking the rejection/acceptance rate.
uint		SampleCount;						// The number of sub-pixel samples.
float		Sharpness;							// The sharpness factor for the output buffer.
float2		TexelSize;							// The size of a texel in screen space.
float		VelocityWeight;						// The velocity weight when evaluating reprojection validity.

// Description:
// The FullscreenVertexIn structure carries the input information for the vertex stage.
struct FullscreenVertexIn
{
#ifdef __ORBIS__
	float4 Position		: POSITION;				// The vertex position.
#else //! __ORBIS__
	float3 Position		: POSITION;				// The vertex position.
#endif //! __ORBIS__
	float2 Uv			: TEXCOORD0;			// The texture coordinates.
};

// Description:
// The FullscreenVertexOut structure carries the output information from the vertex stage.
struct FullscreenVertexOut
{
	float4 Position		: SV_POSITION;			// The projected position.
	float2 Uv			: TEXCOORD0;			// The texture coordinates.
};

// Description:
// The TemporalFilterOutput structure carries the output information from the temporal filtering stage.
struct TemporalFilterOutput
{
	float4 Color		: FRAG_OUTPUT_COLOR0;	// The unjittered color.
	float4 History		: FRAG_OUTPUT_COLOR1;	// The filtered color.
	float2 Velocity		: FRAG_OUTPUT_COLOR2;	// The texel velocity.
#ifdef DEBUG_TEMPORAL
	float4 DebugColor	: FRAG_OUTPUT_COLOR3;	// The debug output.
#endif //! DEBUG_TEMPORAL
};

// Description:
// The ColorDesc structure carries all the information about the colors in the various buffers.
struct ColorDesc
{
	float4	currentColor;						// The color from the current aliased frame.
	float4	historyColor;						// The color reprojected from the history buffer.
	float4	previousColor;						// The color from the unjittered previous frame.
};

// Description:
// The FragmentDesc structure carries all the information necessary for performing the temporal resolve operation.
struct FragmentDesc
{
	float	linearDepth;						// The linear depth for the shaded fragment.
	float2	currentUv;							// The texture coordinates in the current frame.
	float2	historyUv;							// The texture coordinates in the history buffer.
	float2	previousUv;							// The texture coordinates in the previous frame.
	float2	currentVelocity;					// The velocity of the texel in the current frame.
	float2	previousVelocity;					// The velocity of the texel in the previous frame.
};

// Description:
// The NeighborhoodDesc structure carries the color information for performing neighborhood clipping or clamping.
struct NeighborhoodDesc
{
	float4	cmin;								// The minimum color value.
	float4	cmax;								// The maximum color value.
	float4	cavg;								// The average color value.
};

// Description:
// The NearestSamplerState sampler state is a clamping point sampler state.
SamplerState NearestSamplerState
{
	Filter = MIN_MAG_MIP_POINT;
	AddressU = Clamp;
	AddressV = Clamp;
};

// Description:
// The LinearSamplerState sampler state is a clamping linear sampler state.
SamplerState LinearSamplerState
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};

// Description:
// A define for a small epsilon value.
#define FLT_EPS	0.00000001f

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Helper functions.

// Description:
// Gets the luminance from the given color.
// Arguments:
// color - The input color.
// Returns:
// The calculated luminance.
float GetLuminance(in float4 color)
{
#ifdef USE_YCOCG
	return color.x;
#else //! USE_YCOCG
	return 0.2126f * color.x + 0.7152f * color.y + 0.0722f * color.z;
#endif //! USE_YCOCG
}

// Description:
// Clips the input color to the axis-aligned bounding box.
// Arguments:
// boundsMin - The minimum bounds.
// boundsMax - The maximum bounds.
// p - The clipping direction point.
// q - The color to be clipped.
// Returns:
// The clipped color.
float3 ClipAABB(in float3 boundsMin, in float3 boundsMax, in float3 p, in float3 q)
{
#if 1
	float3 p_clip = 0.5f * (boundsMax + boundsMin);
	float3 e_clip = 0.5f * (boundsMax - boundsMin);

	float3 v_clip = q - p_clip;
	float3 v_unit = v_clip / max(e_clip, FLT_EPS);
	float3 a_unit = abs(v_unit);
	float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

	if(ma_unit > 1.0f)
		return p_clip + v_clip / ma_unit;
	else
		return q;	// point inside AABB
#else 
	float3 r = q - p;
	float3 rmax = boundsMax - p;
	float3 rmin = boundsMin - p;

	const float eps = FLT_EPS;

	if(r.x > rmax.x + eps)
		r *= (rmax.x / r.x);
	if(r.y > rmax.y + eps)
		r *= (rmax.y / r.y);
	if(r.z > rmax.z + eps)
		r *= (rmax.z / r.z);

	if(r.x < rmin.x - eps)
		r *= (rmin.x / r.x);
	if(r.y < rmin.y - eps)
		r *= (rmin.y / r.y);
	if(r.z < rmin.z - eps)
		r *= (rmin.z / r.z);

	return p + r;
#endif
}

// Description:
// Converts a depth value from post projection space to view space.
// Assumes the depth is in a 0-1 range.
// Arguments:
// depth - The post projection depth to convert.
// Returns:
// The converted view space depth.
float ConvertDepth(in float depth)
{
#ifdef ORTHO_CAMERA
	const float viewSpaceDepth = -(depth * cameraFarMinusNear + cameraNearFar.x);
#else //! ORTHO_CAMERA
	const float viewSpaceDepth = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
#endif //! ORTHO_CAMERA
	return viewSpaceDepth;
}

// Description:
// Finds the closest fragment in the neighborhood of the given texture coordinates.
// Arguments:
// uv - The texture coordinates.
// Returns:
// The coordinates of the closest fragment.
float3 FindClosestFragment(in float2 uv)
{
	const float2 dd = TexelSize,
				 du = float2(dd.x, 0.0f),
				 dv = float2(0.0f, dd.y);

	// Fetch the depth samples for the top row
	const float3 dtl = float3(-1.0f, -1.0f, DepthBuffer.Sample(NearestSamplerState, uv - dv - du).x),
				 dtc = float3( 0.0f, -1.0f, DepthBuffer.Sample(NearestSamplerState, uv - dv).x),
				 dtr = float3( 1.0f, -1.0f, DepthBuffer.Sample(NearestSamplerState, uv - dv + du).x);

	// Fetch the depth samples for the middle row
	const float3 dml = float3(-1.0f,  0.0f, DepthBuffer.Sample(NearestSamplerState, uv - du).x),
				 dmc = float3( 0.0f,  0.0f, DepthBuffer.Sample(NearestSamplerState, uv).x),
				 dmr = float3( 1.0f,  0.0f, DepthBuffer.Sample(NearestSamplerState, uv + du).x);

	// Fetch the depth samples for the bottom row
	const float3 dbl = float3(-1.0f,  1.0f, DepthBuffer.Sample(NearestSamplerState, uv + dv - du).x),
				 dbc = float3( 0.0f,  1.0f, DepthBuffer.Sample(NearestSamplerState, uv + dv).x),
				 dbr = float3( 1.0f,  1.0f, DepthBuffer.Sample(NearestSamplerState, uv + dv + du).x);

	// Select the closest fragment
	float3 dmin = dtl;
	if(dmin.z > dtc.z) dmin = dtc;
	if(dmin.z > dtr.z) dmin = dtr;

	if(dmin.z > dml.z) dmin = dml;
	if(dmin.z > dmc.z) dmin = dmc;
	if(dmin.z > dmr.z) dmin = dmr;

	if(dmin.z > dbl.z) dmin = dbl;
	if(dmin.z > dbc.z) dmin = dbc;
	if(dmin.z > dbr.z) dmin = dbr;

	return float3(uv + dd.xy * dmin.xy, dmin.z);
}

// Description:
// Converts the given normalized device coordinates into texture coordinates.
// Arguments:
// ndc - The normalized device coordinates.
// Returns:
// The computed texture coordinates.
float2 NDCsToUVs(in float2 ndc)
{
#ifndef __ORBIS__
	return 0.5f * float2(ndc.x, -ndc.y);
#else //! __ORBIS__
	return 0.5f * ndc;
#endif //! __ORBIS__
}

// Description:
// Converts the RGB information into the YCoCg color model.
// Arguments:
// rgb - The RGB color information.
// Returns:
// The converted color information.
float3 RGBToYCoCg(in float3 rgb)
{
	return float3(
		 0.25f * rgb.r + 0.5f * rgb.g + 0.25f * rgb.b,
		 0.5f  * rgb.r                - 0.5f  * rgb.b,
		-0.25f * rgb.r + 0.5f * rgb.g - 0.25f * rgb.b);
}

// Description:
// Converts the YCoCg information into the RGB color model.
// Arguments:
// yCoCg - The YCoCg color information.
// Returns:
// The converted color information.
float3 YCoCgToRGB(in float3 yCoCg)
{
	return float3(
		yCoCg.x + yCoCg.y - yCoCg.z,
		yCoCg.x           + yCoCg.z,
		yCoCg.x - yCoCg.y - yCoCg.z);
}

// Description:
// Resolves the input color.
// Arguments:
// color - The color to be resolved.
// Returns:
// The resolved color.
float4 ResolveColor(in float4 color)
{
#ifdef USE_YCOCG
	return float4(YCoCgToRGB(color.xyz), color.w);
#else //! USE_YCOCG
	return color;
#endif //! USE_YCOCG
}

// Description:
// Samples the color information from the given buffer.
// Arguments:
// buffer - The buffer to be sampling from.
// uv - The texture coordinates.
// Returns:
// The nearest sampled color.
float4 SampleColorNearest(in Texture2D buffer, in float2 uv)
{
	const float4 color = buffer.Sample(NearestSamplerState, uv);

#ifdef USE_YCOCG
	return float4(RGBToYCoCg(color.xyz), color.w);
#else //! USE_YCOCG
	return color;
#endif //! USE_YCOCG
}

// Description:
// Samples the color information from the given buffer.
// Arguments:
// buffer - The buffer to be sampling from.
// uv - The texture coordinates.
// Returns:
// The bilinearly sampled color.
float4 SampleColorLinear(in Texture2D buffer, in float2 uv)
{
#if 0
	const float2 coords  = uv / TexelSize + 0.5f,
				 icoords = floor(coords),
				 fcoords = frac(coords);

	uv = icoords + fcoords * fcoords * (3.0f - 2.0f * fcoords);
	//uv = icoords + fcoords * fcoords * fcoords * (fcoords * (fcoords * 6.0f - 15.0f) + 10.0f);
	uv = (uv - 0.5f) * TexelSize;
#endif

	const float4 color = buffer.Sample(LinearSamplerState, uv);

#ifdef USE_YCOCG
	return float4(RGBToYCoCg(color.xyz), color.w);
#else //! USE_YCOCG
	return color;
#endif //! USE_YCOCG
}

// Description:
// Samples the color information from the given buffer.
// Arguments:
// buffer - The buffer to be sampling from.
// uv - The texture coordinates.
// Returns:
// The bicubicly sampled color.
// Note:
// See GPU Gems 2: "Fast Third-Order Texture Filtering", Sigg & Hadwiger:
// http://http.developer.nvidia.com/GPUGems2/gpugems2_chapter20.html
float4 SampleColorCubic(in Texture2D buffer, in float2 uv)
{
	// w0, w1, w2, and w3 are the four cubic B-spline basis functions
	#define w0(a)	((1.0f / 6.0f) * ((a) * ((a) * (-(a) + 3.0f) - 3.0f) + 1.0f))
	#define w1(a)	((1.0f / 6.0f) * ((a) * (a) * (3.0f * (a) - 6.0f) + 4.0f))
	#define w2(a)	((1.0f / 6.0f) * ((a) * ((a) * (-3.0f * (a) + 3.0f) + 3.0f) + 1.0f))
	#define w3(a)	((1.0f / 6.0f) * ((a) * (a) * (a)))

	// g0 and g1 are the two amplitude functions
	#define g0(a)	(w0(a) + w1(a))
	#define g1(a)	(w2(a) + w3(a))

	// h0 and h1 are the two offset functions
	#define h0(a)	(-1.0f + w1(a) / (w0(a) + w1(a)))
	#define h1(a)	( 1.0f + w3(a) / (w2(a) + w3(a)))

	const float2 coords  = uv / TexelSize + 0.5f,
				 icoords = floor(coords),
				 fcoords = frac(coords);

	const float2 g0 = g0(fcoords),
				 g1 = g1(fcoords),
				 h0 = h0(fcoords),
				 h1 = h1(fcoords);

	const float2 uv0 = (float2(icoords.x + h0.x, icoords.y + h0.y) - 0.5f) * TexelSize.xy,
				 uv1 = (float2(icoords.x + h1.x, icoords.y + h0.y) - 0.5f) * TexelSize.xy,
				 uv2 = (float2(icoords.x + h0.x, icoords.y + h1.y) - 0.5f) * TexelSize.xy,
				 uv3 = (float2(icoords.x + h1.x, icoords.y + h1.y) - 0.5f) * TexelSize.xy;

	const float4 color = g0.y * (g0.x * buffer.Sample(LinearSamplerState, uv0)  +
								 g1.x * buffer.Sample(LinearSamplerState, uv1)) +
						 g1.y * (g0.x * buffer.Sample(LinearSamplerState, uv2)  +
								 g1.x * buffer.Sample(LinearSamplerState, uv3));

#ifdef USE_YCOCG
	return float4(RGBToYCoCg(color.xyz), color.w);
#else //! USE_YCOCG
	return color;
#endif //! USE_YCOCG
}

// Description:
// Gets the color descriptor.
// Arguments:
// fragmentDesc - The fragment descriptor.
// Returns:
// The color information.
ColorDesc GetColorDesc(in FragmentDesc fragmentDesc)
{
	ColorDesc Out;

	Out.currentColor = SampleColorNearest(ColorBuffer, fragmentDesc.currentUv);
	Out.historyColor = SampleColorLinear(HistoryBuffer, fragmentDesc.historyUv);
	Out.previousColor = SampleColorNearest(PreviousColorBuffer, fragmentDesc.previousUv);

	return Out;
}

// Description:
// Gets the fragment information.
// Arguments:
// In - The interpolated output from the vertex stage.
// Returns:
// The fragment information.
FragmentDesc GetFragmentDesc(in FullscreenVertexOut In)
{
	FragmentDesc Out;

	// Add the camera jittering for calculating the texture coordinates in the current frame
	Out.currentUv = In.Uv - NDCsToUVs(ProjectionJitter);

	// Fetch the velocity information from the geometry buffers
	// We use the front-most velocity to avoid introducing the aliasing of the current frame into the history buffer
	const float3 closestFragment = FindClosestFragment(Out.currentUv);
	const float2 currentVelocity = NDCsToUVs(VelocityBuffer.Sample(NearestSamplerState, closestFragment.xy).xy);

	// Populate the fragment output structure
	Out.linearDepth = ConvertDepth(closestFragment.z);
	Out.historyUv = In.Uv - currentVelocity;
	Out.currentVelocity = currentVelocity;
	Out.previousVelocity = PreviousVelocityBuffer1.Sample(NearestSamplerState, Out.historyUv).xy;

	// Calculate the texture coordinates in the N-<SampleCount> frame
	Out.previousUv = Out.historyUv;
	if(SampleCount > 1)
	{
		Out.previousUv -= Out.previousVelocity;
		if(SampleCount > 2)
		{
			Out.previousUv -= PreviousVelocityBuffer2.Sample(NearestSamplerState, Out.previousUv).xy;
			if(SampleCount > 3)
			{
				Out.previousUv -= PreviousVelocityBuffer3.Sample(NearestSamplerState, Out.previousUv).xy;
			}
		}
	}

	return Out;
}

// Description:
// Fetches the color neighborhood information.
// Arguments:
// colorDesc - The color descriptor.
// fragmentDesc - The fragment descriptor.
// Returns:
// The color neighborhood information.
// Note:
// Original implementation can be found here:
// https://github.com/playdeadgames/temporal
NeighborhoodDesc GetNeighborhoodDesc(in ColorDesc colorDesc, in FragmentDesc fragmentDesc)
{
	NeighborhoodDesc Out;

	// Calculate the subpixel motion
	const float _SubpixelThreshold = 0.5f;
	const float _GatherBase = 0.5f;
	const float _GatherSubpixelMotion = 0.1666f;
	float2 texel_vel = fragmentDesc.currentVelocity / TexelSize;
	float texel_vel_mag = length(texel_vel) * fragmentDesc.linearDepth;
	float k_subpixel_motion = saturate(_SubpixelThreshold / (FLT_EPS + texel_vel_mag));
	float k_min_max_support = _GatherBase + _GatherSubpixelMotion * k_subpixel_motion;

	// Fetch the neighborhood information
	float2 ss_offset01 = k_min_max_support * float2(-TexelSize.x, TexelSize.y);
	float2 ss_offset11 = k_min_max_support * float2( TexelSize.x, TexelSize.y);
	float4 c00 = SampleColorNearest(ColorBuffer, fragmentDesc.currentUv - ss_offset11);
	float4 c10 = SampleColorNearest(ColorBuffer, fragmentDesc.currentUv - ss_offset01);
	float4 c01 = SampleColorNearest(ColorBuffer, fragmentDesc.currentUv + ss_offset01);
	float4 c11 = SampleColorNearest(ColorBuffer, fragmentDesc.currentUv + ss_offset11);

	// Calculate our axis-aligned bounding box
	Out.cmin = min(c00, min(c10, min(c01, c11)));
	Out.cmax = max(c00, max(c10, max(c01, c11)));
	Out.cavg = (c00 + c10 + c01 + c11) / 4.0f;

#ifdef USE_VARIANCE_CLIPPING
	// Compute the standard deviation from the 2nd order moment
	float4 m2 = c00 * c00 + c10 * c10 + c01 * c01 + c11 * c11;
	float4 sigma = sqrt(m2 / 4.0f - Out.cavg * Out.cavg);

	// Optimize our axis-aligned bounding box
	Out.cmin = max(Out.cavg - Gamma * sigma, Out.cmin);
	Out.cmax = min(Out.cavg + Gamma * sigma, Out.cmax);
#endif //! USE_VARIANCE_CLIPPING

	// Shrink chroma min-max
#ifdef USE_YCOCG
	float2 chroma_extent = 0.25f * 0.5f * (Out.cmax.r - Out.cmin.r);
	float2 chroma_center = colorDesc.currentColor.yz;
	Out.cmin.yz = chroma_center - chroma_extent;
	Out.cmax.yz = chroma_center + chroma_extent;
	Out.cavg.yz = chroma_center;
#endif //! USE_YCOCG

	return Out;
}

// Description:
// Filters the input color for the given neighborhood.
// Arguments:
// colorDesc - The color descriptor.
// neighborhoodDesc - The neighborhood descriptor.
// Returns:
// The filtered color.
float4 FilterColorDescForNeighborhoodDesc(in ColorDesc colorDesc, in NeighborhoodDesc neighborhoodDesc)
{
	float4 filteredColor;

#ifdef USE_CLIPPING
	filteredColor = float4(ClipAABB(neighborhoodDesc.cmin.xyz, neighborhoodDesc.cmax.xyz, clamp(neighborhoodDesc.cavg.xyz, neighborhoodDesc.cmin.xyz, neighborhoodDesc.cmax.xyz), colorDesc.historyColor.xyz), 1.0f);
#else //! USE_CLIPPING
	filteredColor = float4(max(min(colorDesc.historyColor.xyz, neighborhoodDesc.cmax.xyz), neighborhoodDesc.cmin.xyz), 1.0f);
#endif //! USE_CLIPPING

	return filteredColor;
}

// Description:
// Returns true if the given fragment belongs to the sky, false otherwise.
// Arguments:
// fragmentDesc - The fragment descriptor.
// Return Value List:
// true - The fragment is a sky pixel.
// false - The fragment is not a sky pixel.
bool IsSkyPixel(in FragmentDesc fragmentDesc)
{
	return (fragmentDesc.linearDepth == ConvertDepth(1.0f) ? true : false);
}

// Description:
// Gets the feedback weight by comparing the luminance of the two input colors.
// Arguments:
// color0 - The first color to compare.
// color1 - The second color to compare.
// Returns:
// The calculated weight.
// Note:
// Original implementation can be found here:
// https://www.youtube.com/watch?v=WzpLWzGvFK4&t=18m
float GetFeedbackWeight(in float4 color0, in float4 color1)
{
	// Get the luminance for the two colors
	const float luminance0 = GetLuminance(color0),
				luminance1 = GetLuminance(color1);

	// Calculate the unbiased luminance weight
	const float unbiasedLuminanceDiff = abs(luminance0 - luminance1) / max(luminance0, max(luminance1, 0.2f)),
				unbiasedLuminanceWeight = 1.0f - unbiasedLuminanceDiff,
				unbiasedLuminanceWeightSquared = unbiasedLuminanceWeight * unbiasedLuminanceWeight;

	return unbiasedLuminanceWeightSquared;
}

// Description:
// Gets the feedback weight by comparing the lengths of the two input velocities.
// Arguments:
// velocity0 - The first texel velocity.
// velocity1 - The second texel velocity.
// Returns:
// The calculated weight.
float GetVelocityWeight(in float2 velocity0, in float2 velocity1)
{
	return max(0.0f, 1.0f - VelocityWeight * sqrt(abs(length(velocity0) - length(velocity1))));
}

// Description:
// Gets the confidence factor for the reprojected fragment.
// Arguments:
// colorDesc - The color descriptor.
// fragmentDesc - The fragment descriptor.
// Returns:
// The confidence factor between 0 (fragment is disoccluded), to 1 (fragment was present in previous frame).
float GetReprojectionConfidence(in ColorDesc colorDesc, in FragmentDesc fragmentDesc)
{
	float confidenceFactor = 0.0f;

	// Avoid blending our reprojected color into the sky
	if(!IsSkyPixel(fragmentDesc))
	{
		// If the pixel was present in the previous frame, the reprojected velocity should closely match the current velocity, otherwise it means that
		// the current pixel was disoccluded since the previous frame
		confidenceFactor = GetVelocityWeight(fragmentDesc.currentVelocity, fragmentDesc.previousVelocity);

		// Make the filter responsive to reprojection breakage that is due to changes in shading as opposed to disocclusions (typically a moving light);
		// for this we use the N-<SampleCount> frame and compare the aliased colors (this comparison is meaningful since the camera jitters are equal)
		confidenceFactor *= GetFeedbackWeight(colorDesc.currentColor, colorDesc.previousColor);

		// Make the condition harsher to prevent ghosting
		confidenceFactor *= confidenceFactor;
	}

	return smoothstep(0.5f, 1.0f, confidenceFactor);
}

// Description:
// Performs the exponential moving average blend.
// Arguments:
// currentColor - The color in the current frame.
// historyColor - The color from the history buffer.
// Returns:
// The blended color.
float4 BlendColorSamples(in float4 currentColor, in float4 historyColor)
{
	const float alpha = 0.1f;
	return lerp(currentColor, historyColor, 1.0f - alpha);
}

// Description:
// Gets the debug color output.
// Arguments:
// filteredColor - The filtered color.
// colorDesc - The color descriptor.
// fragmentDesc - The fragment descriptor.
// neighborhoodDesc - The neighborhood descriptor.
// Returns:
// The debug output.
float4 GetDebugColor(in float4 filteredColor, in ColorDesc colorDesc, in FragmentDesc fragmentDesc, in NeighborhoodDesc neighborhoodDesc)
{
	#if defined(SHOW_CLIPPED)
	{
		// Mark the clipped samples for debug visualization
		const float distanceToNBB = distance(colorDesc.historyColor.xyz, filteredColor.xyz);
		if(distanceToNBB / length(colorDesc.historyColor.xyz) > 0.05f)
			return float4(1.0f, 0.0f, 0.0f, 1.0f);	// mark larger than 5% changes
		return ResolveColor(filteredColor);
	}
	#elif defined(SHOW_DISOCCLUDED)
	{
		// Output the reprojection confidence factor to help debugging
		const float reprojectionConfidence = GetReprojectionConfidence(colorDesc, fragmentDesc);
		return float4(reprojectionConfidence * colorDesc.historyColor.w * float3(1.0f, 1.0f, 1.0f), 1.0f);
	}
	#else //! SHOW_CLIPPED
	{
		// Output some red for unimplemented debug views
		return float4(1.0f, 0.0f, 0.0f, 1.0f);
	}
	#endif //! SHOW_CLIPPED
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Shader code.

// Description:
// Performs the vertex stage for the full-screen shading pass.
// Arguments:
// In - The vertex parameters.
// Returns:
// The shaded vertex.
FullscreenVertexOut VS_Fullscreen(FullscreenVertexIn In)
{
	FullscreenVertexOut Out;

#ifdef __ORBIS__
	Out.Position = float4(In.Position.xy, 1.0f, 1.0f);
#else //! __ORBIS__
	Out.Position = float4(In.Position.x, -In.Position.y, 1.0f, 1.0f);
#endif //! __ORBIS__
	Out.Uv = In.Uv;

	return Out;
}

// Description:
// Performs the temporal filtering for the temporal anti-aliasing post process.
// Arguments:
// In - The interpolated output from the vertex stage.
// Returns:
// The filtered output.
TemporalFilterOutput PS_TemporalFilter(FullscreenVertexOut In)
{
	TemporalFilterOutput Out;

	// Fetch the color information
	const FragmentDesc fragmentDesc = GetFragmentDesc(In);
	const ColorDesc colorDesc = GetColorDesc(fragmentDesc);

	// Filter the reprojected color using the local color neighborhood
	const NeighborhoodDesc neighborhoodDesc = GetNeighborhoodDesc(colorDesc, fragmentDesc);
	float4 filteredColor = FilterColorDescForNeighborhoodDesc(colorDesc, neighborhoodDesc);

	// Accept some of the previous color based on how confident we are about the reprojection
	const float reprojectionConfidence = GetReprojectionConfidence(colorDesc, fragmentDesc);
	filteredColor = lerp(filteredColor, colorDesc.historyColor, reprojectionConfidence * colorDesc.historyColor.w);

	// Blend into the history buffer
	const float temporalMask = lerp(reprojectionConfidence, colorDesc.historyColor.w, rcp(float(SampleCount)));
	const float4 historyColor = float4(BlendColorSamples(colorDesc.currentColor, filteredColor).xyz, temporalMask);

	// Populate the output structure
	Out.Color = ResolveColor(colorDesc.currentColor);
	Out.History = ResolveColor(historyColor);
	Out.Velocity = fragmentDesc.currentVelocity;
#ifdef DEBUG_TEMPORAL
	Out.DebugColor = GetDebugColor(filteredColor, colorDesc, fragmentDesc, neighborhoodDesc);
#endif //! DEBUG_TEMPORAL

	return Out;
}

// Description:
// Renders the results of our temporal filtering.
// Arguments:
// In - The interpolated output from the vertex stage.
// Returns:
// The anti-aliased color value.
float4 PS_TemporalRender(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
	#ifdef DEBUG_TEMPORAL
	{
		return DebugBuffer.Sample(NearestSamplerState, In.Uv);
	}
	#else //! DEBUG_TEMPORAL
	{
		#ifdef USE_SHARPENING
		{
			float4 sharpenedColor = HistoryBuffer.Sample(NearestSamplerState, In.Uv);

			// Apply the sharpening filter before outputting the frame results
			sharpenedColor += 4.0f * Sharpness * sharpenedColor;
			sharpenedColor -= Sharpness * HistoryBuffer.Sample(NearestSamplerState, In.Uv + TexelSize * float2(-1.0f,  0.0f));
			sharpenedColor -= Sharpness * HistoryBuffer.Sample(NearestSamplerState, In.Uv + TexelSize * float2( 1.0f,  0.0f));
			sharpenedColor -= Sharpness * HistoryBuffer.Sample(NearestSamplerState, In.Uv + TexelSize * float2( 0.0f, -1.0f));
			sharpenedColor -= Sharpness * HistoryBuffer.Sample(NearestSamplerState, In.Uv + TexelSize * float2( 0.0f,  1.0f));

			return sharpenedColor;
		}
		#else //! USE_SHARPENING
		{
			return HistoryBuffer.Sample(NearestSamplerState, In.Uv);
		}
		#endif //! USE_SHARPENING
	}
	#endif //! DEBUG_TEMPORAL
}

// Description:
// Unjitters the jittered input buffer.
// Arguments:
// In - The interpolated output from the vertex stage.
// Returns:
// The unjittered color value.
float4 PS_TemporalUnjitter(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
#ifdef ORTHO_CAMERA
	const float2 uv = In.Uv;	// no jittering for orthographic cameras
#else //! ORTHO_CAMERA
	const float2 uv = In.Uv - NDCsToUVs(ProjectionJitter);
#endif //! ORTHO_CAMERA
	return ColorBuffer.Sample(NearestSamplerState, uv);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Techniques.

BlendState NoBlend
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

DepthStencilState DepthState
{
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE;
};

RasterizerState DefaultRasterState
{
	CullMode = None;
};

#ifndef __ORBIS__

technique11 TemporalFilter
<
	string VpIgnoreContextSwitches[] = { "DEBUG_TEMPORAL", "ORTHO_CAMERA", "USE_CLIPPING", "USE_SHARPENING", "USE_VARIANCE_CLIPPING", "USE_YCOCG", "SHOW_CLIPPED", "SHOW_DISOCCLUDED" };
	string FpIgnoreContextSwitches[] = { "USE_SHARPENING" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Fullscreen()));
		SetPixelShader(CompileShader(ps_5_0, PS_TemporalFilter()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 TemporalRender
<
	string VpIgnoreContextSwitches[] = { "DEBUG_TEMPORAL", "ORTHO_CAMERA", "USE_CLIPPING", "USE_SHARPENING", "USE_VARIANCE_CLIPPING", "USE_YCOCG", "SHOW_CLIPPED", "SHOW_DISOCCLUDED" };
	string FpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "USE_CLIPPING", "USE_VARIANCE_CLIPPING", "USE_YCOCG", "SHOW_CLIPPED", "SHOW_DISOCCLUDED" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Fullscreen()));
		SetPixelShader(CompileShader(ps_5_0, PS_TemporalRender()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 TemporalUnjitter
<
	string VpIgnoreContextSwitches[] = { "DEBUG_TEMPORAL", "ORTHO_CAMERA", "USE_CLIPPING", "USE_SHARPENING", "USE_VARIANCE_CLIPPING", "USE_YCOCG", "SHOW_CLIPPED", "SHOW_DISOCCLUDED" };
	string FpIgnoreContextSwitches[] = { "DEBUG_TEMPORAL", "USE_CLIPPING", "USE_SHARPENING", "USE_VARIANCE_CLIPPING", "USE_YCOCG", "SHOW_CLIPPED", "SHOW_DISOCCLUDED" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Fullscreen()));
		SetPixelShader(CompileShader(ps_5_0, PS_TemporalUnjitter()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__
