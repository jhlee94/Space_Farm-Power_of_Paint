/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

//
// Common depth of field processing code that handle a single axis of the separable blur
// Performs a horizontal blur if HORIZONTAL is defined.
// Inspired by http://gpupro.blogspot.co.uk/2013/09/gpu-pro-4-skylanders-depth-of-field.html

#ifdef HORIZONTAL
PS_OUTPUT RenderDoFPSHorizontal(FullScreenVS_Output Input)
#else // HORIZONTAL
PS_OUTPUT RenderDoFPSVertical(FullScreenVS_Output Input)
#endif // HORIZONTAL
{
#ifdef HORIZONTAL
	const float2 direction = float2(1, 0);
#else
	const float2 direction = float2(0, 1);
#endif // HORIZONTAL

	float2 uv = Input.Tex.xy;

	// Accumulate the blurry image color
	float3 blurResult  = float3(0,0,0);
	float blurWeightSum = 0.0f;

	// Accumulate the near-field color and coverage
	float4 nearResult = float4(0,0,0,0);
	float nearWeightSum = 0.000f;

	float2 uvoff = float2(direction) / float2(textureSize(ColorInput, 0));

#ifdef HORIZONTAL

	// First pass, read z buffer
	float zvalue = DepthBuffer.SampleLevel(PointClampSampler, uv, 0).x;
	float fplane = GetSignedDistanceToFocusPlane(zvalue);
	float packedA = fplane * 0.5f + 0.5f;

#else // HORIZONTAL

	// Second pass, read from previous output
	float packedA = ColorInput.SampleLevel(PointClampSampler, uv, 0).a;
	float fplane = (packedA * 2.0 - 1.0);
	float2 nearoff = float2(direction) / float2(textureSize(NearProcessed, 0));

#endif // HORIZONTAL

	float r_A = fplane * maxCoCRadiusPixels;

	// Map r_A << 0 to 0, r_A >> 0 to 1
	float nearFieldness_A = saturate(r_A * 4.0);

	for (int delta = -maxCoCRadiusPixels; delta <= maxCoCRadiusPixels; ++delta)
	{
		// Packed values
		float2 lookupUV = (uv + uvoff * delta);
		float4 blurInput = ColorInput.SampleLevel(PointClampSampler, lookupUV, 0);

#ifdef HORIZONTAL

		float zvalue2 = DepthBuffer.SampleLevel(PointClampSampler, lookupUV, 0).x;
		float fplane2 = GetSignedDistanceToFocusPlane(zvalue2);

#else // HORIZONTAL

		float fplane2 = (blurInput.a * 2.0 - 1.0);

#endif // HORIZONTAL

		// Signed kernel radius at this tap, in pixels
		float r_B = fplane2 * maxCoCRadiusPixels;

		/////////////////////////////////////////////////////////////////////////////////////////////
		// Compute blurry buffer

		float offset = float(abs(delta) * 5) / (0.001 + abs(r_B)); // 5 based on kernel taps - 1
		float wNormal  = 
			// Only consider mid- or background pixels (allows inpainting of the near-field)
			float(!inNearField(r_B)) *

			// Stretch the kernel extent to the radius at pixel B.
			exp((-0.5f / 36.0f) * offset * offset);	// 36.0f = 6x6 = the extent of the blur

		float weight = lerp(wNormal, 1.0, nearFieldness_A);

		// far + mid-field output 
		blurWeightSum  += weight;
		blurResult += blurInput.rgb * weight;

		///////////////////////////////////////////////////////////////////////////////////////////////
		// Compute near-field super blurry buffer

#ifdef HORIZONTAL

		float nearAlpha = abs(delta) <= r_B ? saturate(r_B * 4.0) : 0.0f;

		// Compute premultiplied-alpha color
		float4 nearInput = float4(blurInput.rgb * nearAlpha, nearAlpha);

#else // HORIZONTAL

		// On the second pass, use the already-available alpha values
		float4 nearInput = NearProcessed.SampleLevel(PointClampSampler, uv + nearoff * delta, 0);

#endif // HORIZONTAL

		// Simplified compare rather than full gaussian kernel
		weight =  float(abs(delta) < nearBlurRadiusPixels);
		nearResult += nearInput * weight;
		nearWeightSum += weight;
	}

	// Normalize the blur results
	PS_OUTPUT Out;
	Out.NearResult = nearResult / max(nearWeightSum, 0.00001); 
	Out.BlurResult = float4(blurResult / blurWeightSum, packedA); // Retain the packed radius for reuse in subsequent passes
	return Out;
}
