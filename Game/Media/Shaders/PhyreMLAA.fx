/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

float4 PixelOffset;

Texture2D <float4> DepthBuffer;
Texture2D <float4> ColorBuffer;
Texture2D <float4> EdgeDetectBuffer;
Texture2D <float4> EdgeLengthBuffer;

float Threshold;
float4 TileUvTransform;

///////////////////////////////////////////////////////////////
// structures /////////////////////
///////////////////////////////////////////////////////////////

struct FullscreenVertexIn
{
#ifdef __ORBIS__
	float4 vertex		: POSITION;
#else //! __ORBIS__
	float3 vertex		: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct FullscreenVertexOut
{
	float4 Position		: SV_POSITION;
	float2 Uv			: TEXCOORD0;
};



sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};


///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

FullscreenVertexOut FullscreenVP(FullscreenVertexIn input)
{
	FullscreenVertexOut output;

	output.Position = float4(input.vertex.xy, 1, 1);
	output.Uv = input.uv;
#ifndef __ORBIS__
	output.Uv.y = 1.0f-output.Uv.y;
#endif //! __ORBIS__
	
	return output;
}

float4 edgeDetect(float2 uv)
{
	float4 centre = ColorBuffer.SampleLevel(LinearClampSampler, uv, 0);
	float4 x1 = ColorBuffer.SampleLevel(LinearClampSampler, uv + float2( PixelOffset.x,0.0f), 0);
	float4 y1 = ColorBuffer.SampleLevel(LinearClampSampler, uv + float2(0.0f, PixelOffset.y), 0);
	float4 xy1 = ColorBuffer.SampleLevel(LinearClampSampler, uv + float2(PixelOffset.x, PixelOffset.y), 0);
	float4 dx = abs(x1 - centre);
	float4 dy = abs(y1 - centre);
	float4 dxy = abs(xy1 - centre);
	float dxRslt = dot(dx.xyz,1.0f);
	float dyRslt = dot(dy.xyz,1.0f);
	float dxyRslt = dot(dxy.xyz,1.0f);
	
	float threshold = 0.2f;
	float dxEdge = dxRslt > threshold;
	float dyEdge = dyRslt > threshold;
	float dxyEdge = dxyRslt > threshold;
		
	return float4(dxEdge, dyEdge, 0.0f, 0.0f);
}

float4 EdgeDetectFP(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
	float4 edgeRslt = edgeDetect(In.Uv);
	return edgeRslt;
}


void generateEdgeLength0(inout float2 rsltDist, float2 uv, float2 dir, float2 edgeMaskX, float2 edgeMaskY)
{
	float threshold = Threshold;
	uv += float2(dir.y,dir.x) * PixelOffset.xy * 0.5f; 

	{
		// scan left
		float2 currUV = uv;
		float inc = 1.0f / 255.0f;
		for (int k = 0; k < 4; ++k)
		{
			currUV -= dir * PixelOffset.xy;
			float4 edge = EdgeDetectBuffer.SampleLevel(LinearClampSampler, currUV, 0);
			
			if(dot(edge.xy,edgeMaskX) > threshold
			|| dot(edge.xy,edgeMaskY) < threshold)
				inc = 0;
				
			rsltDist.x += inc;
		}
	}
		
	{
		// scan right
		float2 currUV = uv;
		float inc = 1.0f / 255.0f;		
		float4 edge = EdgeDetectBuffer.SampleLevel(LinearClampSampler, currUV, 0);
		
		for (int k = 0; k < 4; ++k)
		{						
			if (dot(edge.xy,edgeMaskX) > threshold) 
				inc = 0.0f; // top or bottom edge found					
		
			currUV += dir * PixelOffset.xy;
		
			edge = EdgeDetectBuffer.SampleLevel(LinearClampSampler, currUV, 0);
		
			if ( dot(edge.xy,edgeMaskY) < threshold) 
				inc = 0.0f;			
			rsltDist.y += inc;
		}
	}
}

float generateEdgeLength(float2 uv, float2 dir, float rsltLength, float4 mask)
{
	dir *= PixelOffset.xy * 255.0f;
	float2 currUV = uv + dir * rsltLength;
	for (int k = 0; k < 3; ++k)
	{
		float deltaU = dot(EdgeLengthBuffer.SampleLevel(LinearClampSampler, currUV, 0), mask);
		
		rsltLength += deltaU;
		currUV += dir * deltaU;
	}
	
	return rsltLength;
} 

float4 RenderEdgeLength0FP(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
	float4 dist = 0;
	float2 uv = In.Uv;
	float2 currEdge = EdgeDetectBuffer.SampleLevel(LinearClampSampler, uv, 0).xy;
	generateEdgeLength0(dist.xy, uv, float2(1.0f,0.0f), float2(1.0f,0.0f), float2(0.0f,1.0f));
	generateEdgeLength0(dist.zw, uv, float2(0.0f,1.0f), float2(0.0f,1.0f), float2(1.0f,0.0f));

	return dist;
}
float4 RenderEdgeLengthFP(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
	float4 result;
	float2 uv = In.Uv;
	float4 deltaPos = EdgeLengthBuffer.SampleLevel(LinearClampSampler, uv, 0);
	
	result = deltaPos;
		
	result.x = generateEdgeLength(uv, float2(-1.0f,0.0f), result.x, float4(1.0f,0.0f,0.0f,0.0f));
	result.y = generateEdgeLength(uv, float2(1.0f,0.0f), result.y, float4(0.0f,1.0f,0.0f,0.0f));
	result.z = generateEdgeLength(uv, float2(0.0f,-1.0f), result.z, float4(0.0f,0.0f,1.0f,0.0f));
	result.w = generateEdgeLength(uv, float2(0.0f,1.0f), result.w, float4(0.0f,0.0f,0.0f,1.0f));
		
	return result;
}


//#define DEBUG_COLOURS

half getBlendFactor(half start, half end, half pos, half2 h, half step)
{	
	half slope = (h.y - h.x) / (end + step - start);
	half hb0 = h.x + slope * (pos - start);
	half hb1 = hb0 + step * slope;
	half area = 0.5f * (hb0 + hb1);
	return area;
}

void evaluateMLAAEdge(inout half4 finalCol, inout half weight, float2 uv, half2 edgeDist, half2 edgeDir, half2 blendFactor, float2 edgePixelOffset, half4 debugColor)
{
	half negLength = round(edgeDist.x * 255.f);
	half posLength = round(edgeDist.y * 255.f);
	half len = negLength + posLength + 1;
	float2 startUV = uv + (edgeDir * -PixelOffset.xy * negLength) - edgePixelOffset;
	float2 endUV = uv + (edgeDir * PixelOffset.xy * posLength) - edgePixelOffset;
	
	if (len > 1 && negLength <= posLength) 
	{
		half4 c = (half4)EdgeDetectBuffer.SampleLevel(LinearClampSampler, startUV - (PixelOffset.xy * edgeDir) + edgePixelOffset, 0);	
		if (dot(c.xy,edgeDir) > Threshold)
		{
#ifdef DEBUG_COLOURS
			finalCol += debugColor;
#else
			half b = getBlendFactor(dot(startUV,edgeDir), dot(endUV,edgeDir), dot(uv,edgeDir), blendFactor, dot(PixelOffset.xy,edgeDir));						
			finalCol += (half4)ColorBuffer.SampleLevel(LinearClampSampler, uv + b * ((1-edgeDir) * PixelOffset.xy), 0); 
#endif		
			weight += 1.0;
		}					
	}
	
	if (len > 1 && negLength >= posLength) 
	{
		half4 c = (half4)EdgeDetectBuffer.SampleLevel(LinearClampSampler, endUV + edgePixelOffset, 0);	
		if (dot(c.xy,edgeDir) > Threshold)
		{	
#ifdef DEBUG_COLOURS
			finalCol += debugColor;
#else		
			half b = getBlendFactor(dot(startUV,edgeDir), dot(endUV,edgeDir), dot(uv,edgeDir), -blendFactor, dot(PixelOffset.xy,edgeDir));				
			finalCol += (half4)ColorBuffer.SampleLevel(LinearClampSampler, uv + b * ((1-edgeDir) * PixelOffset.xy), 0); 
#endif				
			weight += 1.0;
		}
	}				
	
}

half4 CalculateMLAA(float2 uv)
{
	half2 edges = (half2)EdgeDetectBuffer.SampleLevel(LinearClampSampler, uv, 0).xy;	
	half2 edgesT = (half2)EdgeDetectBuffer.SampleLevel(LinearClampSampler, uv - float2(0.0f, PixelOffset.y), 0).xy;
	half2 edgesL = (half2)EdgeDetectBuffer.SampleLevel(LinearClampSampler, uv - float2(PixelOffset.x, 0.0f), 0).xy;	
	
	half threshold = Threshold;
	half4 finalCol = 0;
	half weight = 0;

	half4 dist = (half4)EdgeLengthBuffer.SampleLevel(LinearClampSampler, uv, 0);
	half4 distT = (half4)EdgeLengthBuffer.SampleLevel(LinearClampSampler, uv - float2(0.0f, PixelOffset.y), 0);
	half4 distL = (half4)EdgeLengthBuffer.SampleLevel(LinearClampSampler, uv - float2(PixelOffset.x, 0.0f), 0);	
	
	half4 baseColour = (half4)ColorBuffer.SampleLevel(LinearClampSampler, uv, 0);
	
	if(edges.y > threshold)
	{
		evaluateMLAAEdge(finalCol, weight, uv, dist.xy, half2(1.0f,0.0f), half2(0.5f, -0.5f), 0, half4(1.0f,0.0f,0.0f,0.0f));
	}
	if(edgesT.y > threshold)
	{	
		evaluateMLAAEdge(finalCol, weight, uv, distT.xy, half2(1.0f,0.0f), half2(-0.5f, 0.5f), float2(0.0f,PixelOffset.y), half4(0.0f,1.0f,0.0f,0.0f));
	}
	if (edges.x > threshold)
	{
		evaluateMLAAEdge(finalCol, weight, uv, dist.zw, half2(0.0f,1.0f), half2(0.5f, -0.5f), 0, half4(0.0f,0.0f,1.0f,0.0f));
	}
	if (edgesL.x > threshold)
	{
		evaluateMLAAEdge(finalCol, weight, uv, distL.zw, half2(0.0f,1.0f), half2(-0.5f, 0.5f), float2(PixelOffset.x,0.0f), half4(0.0f,0.0f,0.0f,1.0f));
	}
		
#ifdef DEBUG_COLOURS
	if(weight == 0)
		return 0;
	else
	{
		finalCol /= weight;
		//return half4(finalCol.xy, 0.0f,1.0f);
		return half4(finalCol.x+finalCol.y, finalCol.z+finalCol.w, 0.0f,1.0f);
	}
#else			
	if(weight > 0)
		finalCol *= 1.0/weight; 	
	else
		finalCol = baseColour;
	//finalCol += baseColour * saturate(1.0f-(weight*1000.0f));	
	return finalCol;
#endif
}


float4 ApplyMLAAFP(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
	return CalculateMLAA(In.Uv);
}


float4 CopyBufferFP(FullscreenVertexOut In) : FRAG_OUTPUT_COLOR0
{
	return ColorBuffer.SampleLevel(LinearClampSampler, In.Uv, 0);
}

#ifndef __ORBIS__

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
  RenderTargetWriteMask[0] = 15;
};
BlendState LinearBlend 
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = Src_Alpha;
	DestBlend[0] = Inv_Src_Alpha;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	BlendEnable[1] = FALSE;
	RenderTargetWriteMask[0] = 15;
};
DepthStencilState NoDepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};
RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};


technique11 RenderMLAA
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, ApplyMLAAFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}
technique11 CopyNoMLAA
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, CopyBufferFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderEdgeDetect
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, EdgeDetectFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}


technique11 RenderEdgeLength0
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderEdgeLength0FP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}
technique11 RenderEdgeLength
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderEdgeLengthFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

#endif //! __ORBIS__
