/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global shader parameters.

// Un-tweakables
float4x4 World						: World;
float4x4 WorldView					: WorldView;
float4x4 WorldViewProjection		: WorldViewProjection;
float selectionIDColor;
float4 constantColor = {1,1,1,1};
float4 multipleSelectionIDColor;
float GridFadeStartDistance;
float GridFadeDistanceScale;

#define MatrixMultiply(x,y) mul(y,x)

#include "PhyreTerrainSharedFx.h"

#ifndef __ORBIS__

// Context switches
bool PhyreContextSwitches
<
	string ContextSwitchNames[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>;

#endif //! __ORBIS__

sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

#ifndef __ORBIS__

BlendState NoBlend
{
	BlendEnable[0] = FALSE;
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
DepthStencilState DepthState
{
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Less_Equal;
	StencilEnable = FALSE; 
};
DepthStencilState NoDepthWriteState
{
	DepthEnable = TRUE;
	DepthWriteMask = Zero;
	DepthFunc = Less_Equal;
	StencilEnable = FALSE; 
};
DepthStencilState NoDepthState
{
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less_Equal;
	StencilEnable = FALSE; 
};

RasterizerState DefaultRasterState
{
	CullMode = Front;
};

RasterizerState NoCullRasterState
{
	CullMode = None;
};

RasterizerState WireRasterState
{
	CullMode = None;
	FillMode = WireFrame;
};
RasterizerState SolidRasterState
{
	CullMode = None;
	FillMode = Solid;
};
#endif //! __ORBIS__

#ifdef SKINNING_ENABLED

	#if 0
		// This is the standard non constant buffer implementation.
		#define NUM_SKIN_TRANSFORMS 80 // Note: This number is mirrored in Core as PD_MATERIAL_SKINNING_MAX_GPU_BONE_COUNT
		float4x4 BoneTransforms[NUM_SKIN_TRANSFORMS] : BONETRANSFORMS;
	#else
		// This is the structured buffer implementation that uses the structured buffer from PhyreCoreShaderShared.h
		#define BoneTransforms BoneTransformConstantBuffer
	#endif

void EvaluateSkinPosition4Bones( inout float3 position, float4 weights, uint4 boneIndices )
{
	uint indexArray[4] = {boneIndices.x,boneIndices.y,boneIndices.z,boneIndices.w};
	float4 inPosition = float4(position,1);
	
 	position =
		mul(inPosition, BoneTransforms[indexArray[0]]).xyz * weights.x
	+	mul(inPosition, BoneTransforms[indexArray[1]]).xyz * weights.y
	+	mul(inPosition, BoneTransforms[indexArray[2]]).xyz * weights.z
	+	mul(inPosition, BoneTransforms[indexArray[3]]).xyz * weights.w;
}

#endif // SKINNING_ENABLED

#ifdef INSTANCING_ENABLED
	struct InstancingInput
	{
		float4	InstanceTransform0	: InstanceTransform0;
		float4	InstanceTransform1	: InstanceTransform1;
		float4	InstanceTransform2	: InstanceTransform2;
	};

	void ApplyInstanceTransformVertex(InstancingInput IN, inout float3 toTransform)
	{
		float3 instanceTransformedPosition;
		instanceTransformedPosition.x = dot(IN.InstanceTransform0, float4(toTransform,1));
		instanceTransformedPosition.y = dot(IN.InstanceTransform1, float4(toTransform,1));
		instanceTransformedPosition.z = dot(IN.InstanceTransform2, float4(toTransform,1));
		toTransform = instanceTransformedPosition;
	}

	void ApplyInstanceTransformNormal(InstancingInput IN, inout float3 toTransform)
	{
		float3 instanceTransformedNormal;
		instanceTransformedNormal.x = dot(IN.InstanceTransform0.xyz, toTransform);
		instanceTransformedNormal.y = dot(IN.InstanceTransform1.xyz, toTransform);
		instanceTransformedNormal.z = dot(IN.InstanceTransform2.xyz, toTransform);
		toTransform = instanceTransformedNormal;
	}
#endif //! INSTANCING_ENABLED

struct ObjectSelectionVPInput
{
#ifdef __ORBIS__
	float4 Position		: POSITION;
#else //! __ORBIS__
	float3 Position		: POSITION;
#endif //! __ORBIS__
};

#ifdef SKINNING_ENABLED
	struct ObjectSelectionVPInputWithSkinning
	{
	#ifdef __ORBIS__
		float4 SkinnableVertex	: POSITION;
	#else //! __ORBIS__
		float3 SkinnableVertex	: POSITION;
	#endif //! __ORBIS__
		float3 SkinnableNormal	: NORMAL;
		uint4 SkinIndices		: BLENDINDICES;
		float4 SkinWeights		: BLENDWEIGHTS;
	};
#endif // SKINNING_ENABLED

// Single Pixel Selection

struct SingleSelectionVPOutput
{
	float4 Position		 : SV_POSITION;
	float3 WorldPosition : TEXCOORD0;
	float ViewSpaceZ	 : TEXCOORD1;
};

struct SingleSelectionFPOutput
{
	float4 IdColorAndDepth	: FRAG_OUTPUT_COLOR0;
	float4 FaceNormal		: FRAG_OUTPUT_COLOR1;
};

#ifdef SKINNING_ENABLED
// Single selection render vertex shader
SingleSelectionVPOutput SingleSelectionVP(ObjectSelectionVPInputWithSkinning IN)
{
	SingleSelectionVPOutput OUT;

	float3 position = IN.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, (unsigned int4)IN.SkinIndices);
	OUT.Position = mul(float4(position, 1.0f), ViewProjection);
	OUT.WorldPosition = position;
	OUT.ViewSpaceZ = mul(float4(position, 1.0f), View).z;
	
	return OUT;
}

#else // SKINNING_ENABLED

// Single selection render vertex shader
SingleSelectionVPOutput SingleSelectionVP(ObjectSelectionVPInput IN)
{
	SingleSelectionVPOutput OUT;

	float3 position = IN.Position.xyz;
	OUT.Position = mul(float4(position, 1.0f), WorldViewProjection);
	OUT.WorldPosition = mul(float4(position, 1.0f), World).xyz;
	OUT.ViewSpaceZ = mul(float4(position, 1.0f), WorldView).z;
	
	return OUT;
}
#endif // SKINNING_ENABLED

#ifdef __ORBIS__
	//! Set the output format for picking to be 32 bit.
	#ifdef PHYRE_ENTRYPOINT_SingleSelectionFP
		#pragma PSSL_target_output_format(default FMT_32_ABGR)
	#else //! PHYRE_ENTRYPOINT_SingleSelectionFP
		#pragma PSSL_target_output_format(default FMT_FP16_ABGR)
	#endif //! PHYRE_ENTRYPOINT_SingleSelectionFP
#endif //! __ORBIS__

// Single selection render fragment shader
SingleSelectionFPOutput SingleSelectionFP(SingleSelectionVPOutput IN)
{
	SingleSelectionFPOutput OUT;
	
	// Face Normal calculation
	
	float3 dx = ddx(IN.WorldPosition);
	float3 dy = ddy(IN.WorldPosition);
	float epsilon = 0.00001f;
	
	if(length(dx) > epsilon)
		dx = normalize(dx);
	if(length(dy) > epsilon)
		dy = normalize(dy);
	
	float3 faceNormal = -cross(dx,dy);
	if(length(faceNormal) > epsilon)
		faceNormal = normalize(faceNormal);

	OUT.FaceNormal = float4(faceNormal * 0.5f + 0.5f, 1.0f); 
	OUT.IdColorAndDepth = float4(selectionIDColor, abs(IN.ViewSpaceZ), sign(IN.ViewSpaceZ), 0.0f);
	return OUT;
}

#ifndef __ORBIS__

technique11 SingleSelection
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, SingleSelectionVP() ) );
		SetPixelShader( CompileShader( ps_4_0, SingleSelectionFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

technique11 SingleSelectionSolid
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, SingleSelectionVP() ) );
		SetPixelShader( CompileShader( ps_4_0, SingleSelectionFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__

// Multiple Pixel Selection

struct MultipleSelectionVPOutput
{
	float4 Position		 : SV_POSITION;
};

struct MultipleSelectionFPOutput
{
	float4 IdColor	     : FRAG_OUTPUT_COLOR0;
};

#ifdef SKINNING_ENABLED

// Multiple selection render vertex shader
MultipleSelectionVPOutput MultipleSelectionVP(ObjectSelectionVPInputWithSkinning IN)
{
	MultipleSelectionVPOutput OUT;

	float3 position = IN.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, (unsigned int4)IN.SkinIndices);
	OUT.Position = mul(float4(position, 1.0f), ViewProjection);
	
	return OUT;
}
#else // SKINNING_ENABLED

// Multiple selection render vertex shader
MultipleSelectionVPOutput MultipleSelectionVP(ObjectSelectionVPInput IN)
{
	MultipleSelectionVPOutput OUT;

	OUT.Position = mul(float4(IN.Position.xyz, 1.0f), WorldViewProjection);
	return OUT;
}
#endif // SKINNING_ENABLED

// Multiple selection render fragment shader
MultipleSelectionFPOutput MultipleSelectionFP()
{
	MultipleSelectionFPOutput OUT;
	
	OUT.IdColor = multipleSelectionIDColor;
	return OUT;
}

#ifndef __ORBIS__

technique11 MultipleSelection
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, MultipleSelectionVP() ) );
		SetPixelShader( CompileShader( ps_4_0, MultipleSelectionFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

technique11 MultipleSelectionSolid
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, MultipleSelectionVP() ) );
		SetPixelShader( CompileShader( ps_4_0, MultipleSelectionFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( SolidRasterState );
	}
}

#endif //! __ORBIS__

/////////////////////////////////////////////////////////////

#ifdef SKINNING_ENABLED
struct FlatColorVPInputWithSkinning
{
#ifdef __ORBIS__
	float4 SkinnableVertex	: POSITION;
#else //! __ORBIS__
	float3 SkinnableVertex	: POSITION;
#endif //! __ORBIS__
	float3 SkinnableNormal	: NORMAL;
	uint4 SkinIndices		: BLENDINDICES;
	float4 SkinWeights		: BLENDWEIGHTS;

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED
};

#ifdef INSTANCING_ENABLED
void ApplyInstanceTransform(inout FlatColorVPInputWithSkinning IN)
{
	ApplyInstanceTransformVertex(IN.instancingInput, IN.SkinnableVertex.xyz);
	ApplyInstanceTransformNormal(IN.instancingInput, IN.SkinnableNormal.xyz);
}
#endif //! INSTANCING_ENABLED
#endif // SKINNING_ENABLED

struct FlatColorVPInput
{
#ifdef __ORBIS__
	float4 Position			: POSITION;
#else //! __ORBIS__
	float3 Position			: POSITION;
#endif //! __ORBIS__

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED
};

#ifdef INSTANCING_ENABLED
	void ApplyInstanceTransform(inout FlatColorVPInput IN)
	{
		ApplyInstanceTransformVertex(IN.instancingInput, IN.Position.xyz);
	}
#endif //! INSTANCING_ENABLED

struct FlatColorVPOutput
{
	float4 Position		: SV_POSITION;
};


struct FlatColorFPOutput
{
	float4 Color	     : FRAG_OUTPUT_COLOR0;
};

#ifdef SKINNING_ENABLED
// Simple vertex shader
FlatColorVPOutput FlatColorVP(FlatColorVPInputWithSkinning IN)
{
#ifdef INSTANCING_ENABLED
	ApplyInstanceTransform(IN);
#endif //! INSTANCING_ENABLED

	FlatColorVPOutput OUT;

	float3 position = IN.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, (unsigned int4)IN.SkinIndices);
	OUT.Position = mul(float4(position, 1.0f), ViewProjection);
	
	return OUT;
}

#else // SKINNING_ENABLED

// Simple vertex shader
FlatColorVPOutput FlatColorVP(FlatColorVPInput IN)
{
#ifdef INSTANCING_ENABLED
	ApplyInstanceTransform(IN);
#endif //! INSTANCING_ENABLED

	FlatColorVPOutput OUT;

	OUT.Position = mul(float4(IN.Position.xyz, 1.0f), WorldViewProjection);
	
	return OUT;
}
#endif // SKINNING_ENABLED

// Simple fragment shader
FlatColorFPOutput FlatColorFP()
{
	FlatColorFPOutput OUT;
	
	OUT.Color = constantColor;

	return OUT;
}

#ifndef __ORBIS__

technique11 FlatColor
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, FlatColorVP() ) );
		SetPixelShader( CompileShader( ps_4_0, FlatColorFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

technique11 FlatColorTransparent
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, FlatColorVP() ) );
		SetPixelShader( CompileShader( ps_4_0, FlatColorFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthWriteState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

technique11 Outline
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, FlatColorVP() ) );
		SetPixelShader( CompileShader( ps_4_0, FlatColorFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( WireRasterState );	
	}
}

#endif //! __ORBIS__


//////////////////////////////////////////////////////////////////////////////

struct ManipulatorVPInput
{
#ifdef __ORBIS__
	float4 Position		: POSITION;
#else //! __ORBIS__
	float3 Position		: POSITION;
#endif //! __ORBIS__
};


struct ManipulatorVPOutput
{
	float4 Position		: SV_POSITION;
};


struct ManipulatorFPOutput
{
	float4 Color	     : FRAG_OUTPUT_COLOR0;
};

// Simple vertex shader.
ManipulatorVPOutput ManipulatorVP(ManipulatorVPInput IN)
{
	ManipulatorVPOutput OUT;

	OUT.Position = mul(float4(IN.Position.xyz, 1), WorldViewProjection);
	OUT.Position.z = 0;
	
	return OUT;
}

// Simple fragment shader.
ManipulatorFPOutput ManipulatorFP()
{
	ManipulatorFPOutput OUT;
	
	OUT.Color = constantColor;

	return OUT;
}

#ifndef __ORBIS__

technique11 ManipulatorAxis
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, ManipulatorVP() ) );
		SetPixelShader( CompileShader( ps_4_0, ManipulatorFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState(NoCullRasterState);
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////////////////////////

// WorldAxes vertex shader
FlatColorVPOutput WorldAxesVP(FlatColorVPInput IN)
{
	FlatColorVPOutput OUT;

	// Set the rotation matrix
	OUT.Position = mul(float4(mul(float4(IN.Position.xyz,0), WorldView).xyz, 1.0f), Projection);

	// Offset to bottom left of screen.
	float aspect = Projection._m11/Projection._m00;
	float maintainSizeScale = 720.0f/ViewportWidthHeight.y;
	float inset = 0.2f * maintainSizeScale;
	float4 screenOffset = float4(-1.0f + inset/aspect, -1.0f + inset, 0.0f, 0.0f);
	OUT.Position = OUT.Position + screenOffset;
	OUT.Position.z = 0.0f;
	
	return OUT;
}

#ifndef __ORBIS__

technique11 WorldAxes
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, WorldAxesVP() ) );
		SetPixelShader( CompileShader( ps_4_0, FlatColorFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////////////////////////

struct CameraManipulatorVPInput
{
#ifdef __ORBIS__
	float4 Position		: SV_POSITION;
#else //! __ORBIS__
	float3 Position		: SV_POSITION;
#endif //! __ORBIS__
	float3 Normal		: NORMAL;
};

struct CameraManipulatorVPOutput
{
	float4 Position		: SV_POSITION;
	float4 ViewSpacePos	: TEXCOORD0;	
};

// Camera manipulator vertex shader.
CameraManipulatorVPOutput CameraManipulatorVP(CameraManipulatorVPInput IN)
{
	CameraManipulatorVPOutput OUT;

	// Set the rotation matrix
	
	OUT.ViewSpacePos = float4(mul(float4(IN.Position.xyz,0.0),WorldView).xyz, 1.0f);
	OUT.Position = mul(OUT.ViewSpacePos, Projection);

	// Offset to top right of screen.
	float aspect = Projection._m11/Projection._m00;
	float maintainSizeScale = 720.0f/ViewportWidthHeight.y;
	float inset = 0.2f * maintainSizeScale;
	float4 screenOffset = float4(1.0f - inset/aspect, 1.0f - inset, 0.0f, 0.0f);
	OUT.Position = OUT.Position + screenOffset;

	// Set the depth value.
	OUT.Position.z = OUT.ViewSpacePos.z / 10000.0f;

	return OUT;
}

// Camera manipulator lit fragment shader
ManipulatorFPOutput CameraManipulatorLitFP(CameraManipulatorVPOutput IN)
{
	ManipulatorFPOutput OUT;
	
	// Do lighting in camera space.
	float3 P = IN.ViewSpacePos.xyz;
	float3 N = -cross(normalize(ddx(P)), normalize(ddy(P)));
	float3 L = float3(0,0,1);

	// Taking the absolute value of the dot product because ddy() is flipped on GXM meaning N would be negated.
	OUT.Color = constantColor * abs(dot(N,L));

	return OUT;
}

// Flat fragment shader
ManipulatorFPOutput CameraManipulatorFlatFP(CameraManipulatorVPOutput IN)
{
	ManipulatorFPOutput OUT;
	
	OUT.Color = constantColor;

	return OUT;
}

// Camera Indicator Selection vertex shader
SingleSelectionVPOutput CameraIndicatorSelectionVP(ObjectSelectionVPInput IN)
{
	SingleSelectionVPOutput OUT;

	OUT.WorldPosition = mul(float4(IN.Position.xyz,0.0f), WorldView).xyz;
	OUT.Position = mul(float4(OUT.WorldPosition, 1.0f), Projection);
	OUT.Position.z = 0.0f;
	OUT.ViewSpaceZ = 0.0f;

	return OUT;
}

// Camera Indicator Selection fragment shader
SingleSelectionFPOutput CameraIndicatorSelectionFP(SingleSelectionVPOutput IN)
{
	SingleSelectionFPOutput OUT;

	OUT.FaceNormal = float4(0.0f, 0.0f, 1.0f, 0.0f);
	OUT.IdColorAndDepth = float4(selectionIDColor, -1.0f, 1.0f, 0.0f);

	return OUT;
}

#ifndef __ORBIS__

technique11 SingleSelectionCameraIndicator
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, CameraIndicatorSelectionVP() ) );
		SetPixelShader( CompileShader( ps_4_0, CameraIndicatorSelectionFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////////////////////////

struct ManipulatorHiddenLineVPOutput
{
	float4 Position		: SV_POSITION;
	float3 ViewSpaceCentreToPos : TEXCOORD0;
	float3 ViewSpaceCentreToCam : TEXCOORD1;
};

// Simple vertex shader which doesnt project.
ManipulatorHiddenLineVPOutput ManipulatorHiddenLineVP(ManipulatorVPInput IN)
{
	ManipulatorHiddenLineVPOutput OUT;
	OUT.Position = mul(float4(IN.Position.xyz, 1), WorldViewProjection);
	OUT.Position.z = 0.0f;
	
	OUT.ViewSpaceCentreToPos = normalize( mul(float4(normalize( mul(float4(IN.Position.xyz, 1), World).xyz - mul(float4(0,0,0,1), World).xyz ),0),View  )).xyz;
#ifdef ORTHO_CAMERA
	OUT.ViewSpaceCentreToCam = float3(0,0,1);
#else // ORTHO_CAMERA
	OUT.ViewSpaceCentreToCam = -normalize( mul(mul(float4(0,0,0,1),World),View).xyz) ;
#endif // ORTHO_CAMERA
	return OUT;
}

// Simple fragment shader
ManipulatorFPOutput ManipulatorHiddenLineFP(ManipulatorHiddenLineVPOutput IN)
{
	ManipulatorFPOutput OUT;
	
	half drawMeOrNot = half(dot(IN.ViewSpaceCentreToPos, IN.ViewSpaceCentreToCam));

	half alpha = half(saturate(drawMeOrNot * 5.0f));
	clip(alpha);
	OUT.Color = constantColor;
	OUT.Color.w *= alpha;
	
	return OUT;
}

#ifndef __ORBIS__

technique11 ManipulatorAxisHiddenLine
<
	string VpIgnoreContextSwitches[] = {"SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, ManipulatorHiddenLineVP() ) );
		SetPixelShader( CompileShader( ps_4_0, ManipulatorHiddenLineFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__

///////////////////////////////////////////////////////////////////////////////////

struct MultipleSelectionHiddenLineVPOutput
{
	float4 Position		 : SV_POSITION;
	float3 ViewSpaceCentreToPos : TEXCOORD1;
	float3 ViewSpaceCentreToCam : TEXCOORD2;
};

struct MultipleSelectionHiddenLineFPOutput
{
	float4 IdColor	     : FRAG_OUTPUT_COLOR0;
};


// Multiple selection render vertex shader

// Multiple selection render vertex shader
MultipleSelectionHiddenLineVPOutput MultipleSelectionHiddenLineVP(ObjectSelectionVPInput IN)
{
	MultipleSelectionHiddenLineVPOutput OUT;
	OUT.Position = mul(float4(IN.Position.xyz, 1), WorldViewProjection);
	
	// Get the vectors for needed for hidden line clipping
	OUT.ViewSpaceCentreToPos = normalize(mul(float4(normalize(mul(float4(IN.Position.xyz, 1), World).xyz - mul(float4(0,0,0,1), World).xyz ), 0), View)).xyz;
#ifdef ORTHO_CAMERA
	OUT.ViewSpaceCentreToCam = float3(0,0,1);
#else // ORTHO_CAMERA
	OUT.ViewSpaceCentreToCam = -normalize(mul(mul(float4(0,0,0,1),World),View).xyz) ;
#endif // ORTHO_CAMERA

	return OUT;
}

// Multiple selection render fragment shader
MultipleSelectionHiddenLineFPOutput MultipleSelectionHiddenLineFP(MultipleSelectionHiddenLineVPOutput IN)
{
	MultipleSelectionHiddenLineFPOutput OUT;

	// Clip the hidden lines
	half drawMeOrNot = half(dot(IN.ViewSpaceCentreToPos, IN.ViewSpaceCentreToCam));
	half alpha = drawMeOrNot;
	clip(alpha + 0.1f);
	
	OUT.IdColor = multipleSelectionIDColor;

	return OUT;
}

#ifndef __ORBIS__

technique11 MultipleSelectionHiddenLine
<
	string VpIgnoreContextSwitches[] = {"SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, MultipleSelectionHiddenLineVP() ) );
		SetPixelShader( CompileShader( ps_4_0, MultipleSelectionHiddenLineFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );			
	}
}

#endif //! __ORBIS__

///////////////////////////////////////////////////////////////////////////////////

struct SingleSelectionHiddenLineVPOutput
{
	float4 Position		 : SV_POSITION;
	float3 WorldPosition : TEXCOORD0;
	float ViewSpaceZ	 : TEXCOORD1;

	float3 ViewSpaceCentreToPos : TEXCOORD2;
	float3 ViewSpaceCentreToCam : TEXCOORD3;

};

struct SingleSelectionHiddenLineFPOutput
{
	float IdColor	     : FRAG_OUTPUT_COLOR0;
	float3 FaceNormal	 : FRAG_OUTPUT_COLOR1;
	float Depth			 : FRAG_OUTPUT_COLOR2;
};

// Single selection render vertex shader
SingleSelectionHiddenLineVPOutput SingleSelectionHiddenLineVP(ObjectSelectionVPInput IN)
{
	SingleSelectionHiddenLineVPOutput OUT;
	
	OUT.Position = mul(float4(IN.Position.xyz, 1), WorldViewProjection);	
	OUT.Position.z = 0.0f;
	OUT.ViewSpaceCentreToPos = normalize(mul(float4(normalize( mul(float4(IN.Position.xyz, 1), World).xyz - mul(float4(0,0,0,1), World).xyz ),0),View)).xyz;
#ifdef ORTHO_CAMERA
	OUT.ViewSpaceCentreToCam = float3(0,0,1);
#else // ORTHO_CAMERA
	OUT.ViewSpaceCentreToCam = -normalize( mul(mul(float4(0,0,0,1),World),View).xyz);
#endif // ORTHO_CAMERA
	
	OUT.WorldPosition = mul(float4(IN.Position.xyz, 1.0f), World).xyz;
	OUT.ViewSpaceZ = mul(float4(IN.Position.xyz, 1), WorldView).z;
	
	return OUT;
}

// Single selection render fragment shader
SingleSelectionHiddenLineFPOutput SingleSelectionHiddenLineFP(SingleSelectionHiddenLineVPOutput IN)
{
	SingleSelectionHiddenLineFPOutput OUT;
	
	half drawMeOrNot = half(dot(IN.ViewSpaceCentreToPos, IN.ViewSpaceCentreToCam));

	half alpha = half(drawMeOrNot);
	clip(alpha);
	OUT.IdColor = selectionIDColor;

	// Face Normal calculation
	half3 faceNormal = (half3)-normalize(cross(normalize(ddx(IN.WorldPosition)), normalize(ddy(IN.WorldPosition))));
	OUT.FaceNormal = float3(faceNormal * 0.5f + 0.5f); 
	OUT.Depth = abs(IN.ViewSpaceZ);

	return OUT;
}

#ifndef __ORBIS__

technique11 SingleSelectionHiddenLine
<
	string VpIgnoreContextSwitches[] = {"SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, MultipleSelectionHiddenLineVP() ) );
		SetPixelShader( CompileShader( ps_4_0, MultipleSelectionHiddenLineFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////////////////////////

// Simple vertex shader.
struct GridVPOutput
{
	float4 Position		: SV_POSITION;
	float3 ViewPosition : TEXCOORD0;
	float4 DepthPos		: TEXCOORD1;
};

#ifdef __ORBIS__
GridVPOutput RenderGridVP(float4 Position : POSITION)
#else //! __ORBIS__
GridVPOutput RenderGridVP(float3 Position : POSITION)
#endif //! __ORBIS
{
	GridVPOutput Out;
	Out.Position = mul(float4(Position.xyz, 1), WorldViewProjection);
	float4 viewPos =  mul(float4(Position.xyz, 1), WorldView);
	Out.ViewPosition = viewPos.xyz;

	viewPos.z -= 0.1f;
	Out.DepthPos = mul(viewPos, Projection);
	return Out;
}

// Simple fragment shader
float4 RenderGridFP(GridVPOutput In, out float Depth : FRAG_OUTPUT_DEPTH) : FRAG_OUTPUT_COLOR0
{
#ifdef __ORBIS__
	Depth = ((In.DepthPos.z / In.DepthPos.w) + 1.0f) * 0.5f;
#else
	Depth = In.DepthPos.z / In.DepthPos.w;
#endif //! __ORBIS__

	float dist = length(In.ViewPosition);
	float fadeValue = 1.0f - saturate((dist - GridFadeStartDistance) * GridFadeDistanceScale);
	return constantColor * float4(1.0f,1.0f,1.0f,fadeValue);
}

#ifndef __ORBIS__

technique11 RenderGrid
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, RenderGridVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderGridFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

//////////////////////////////////////////////////////////////////////////////

technique11 RenderBoundBox
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, RenderGridVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderGridFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__

// Simple vertex shader.
struct RenderTransparentVPOutput
{
	float4 Position		: SV_POSITION;
};

RenderTransparentVPOutput RenderTransparentVP(float4 Position	: POSITION)
{
	RenderTransparentVPOutput Out;
	Out.Position = mul(float4(Position.xyz, 1), WorldViewProjection);
	return Out;
}
// Simple fragment shader
float4 RenderTransparentFP() : FRAG_OUTPUT_COLOR0
{
	return constantColor;
}

#ifndef __ORBIS__

technique11 RenderTransparentPass
<
	string PhyreRenderPass = "Transparent";
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, RenderTransparentVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderTransparentFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////////////////////////

Texture2D <float4> BitmapFontTexture;
float3 textColor = { 1.0f, 1.0f, 1.0f };
float CameraAspectRatio;

struct VPInput
{
#ifdef __ORBIS__
	float4 position		: POSITION;
#else //! __ORBIS__
	float2 position		: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct VPOutput
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
};

VPOutput TextVP(VPInput IN)
{
	VPOutput OUT;
	
	OUT.position = mul(float4(IN.position.xy, 1.0f, 1.0f), World);
	OUT.position.x *= CameraAspectRatio;
	OUT.uv = IN.uv;
	
	return OUT;
}

float4 TextFP(VPOutput IN) : FRAG_OUTPUT_COLOR0
{
	return float4(textColor, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
}

#ifndef __ORBIS__

technique11 RenderText_AlphaBlend
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );	
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////////////////////////

Texture2D				TerrainStagingTexture;
uint2					TerrainStagingTextureOffset;
RWTexture2D<float4>		TerrainPhysicalTexture;
uint2					TerrainPhysicalTextureOffset;
uint					TerrainPhysicalMipLevel;
uint2					TerrainMaxCopyCoordinates;

[numthreads(8, 8, 1)]
void GameEditTerrainTextureCopyCs(uint3 In : SV_DispatchThreadID)
{
	uint2 xy = min(In.xy, TerrainMaxCopyCoordinates);

	TerrainPhysicalTexture[int2(TerrainPhysicalTextureOffset + xy)] = TerrainStagingTexture[int2(TerrainStagingTextureOffset + (xy << TerrainPhysicalMipLevel))];
}

#ifndef __ORBIS__

technique11 TerrainFlushIntermediateTexture
<
	string PhyreRenderPass = "TerrainTextureCopy";
>
{
	pass pass0
	{
		SetComputeShader( CompileShader( cs_5_0, GameEditTerrainTextureCopyCs() ) );
	}
}

#endif //! __ORBIS__

////////////////////////////////////
// for copying the postprocessing buffer to the backbuffer

Texture2D <float4> GEColorBuffer;

SamplerState GEColorBufferSampler
{
	Filter = MIN_MAG_MIP_POINT;
	AddressU = WRAP;
	AddressV = WRAP;
	AddressW = WRAP;
	MipLODBias = 0;
	MaxAnisotropy = 1;
	MinLOD = 0;
	MaxLOD = 0;
};

struct GEFullscreenVertexIn
{
#ifdef __ORBIS__
	float4 vertex	: POSITION;
#else //! __ORBIS__
	float3 vertex	: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct GEFullscreenVertexOut
{
	float4 position : SV_POSITION;
	float2 uv : TEXCOORD0;
};

GEFullscreenVertexOut GameEditCopyShaderVP(GEFullscreenVertexIn input)
{
	GEFullscreenVertexOut output;

#ifdef __ORBIS__
	output.position = float4(input.vertex.xy, 1, 1);
#else //! __ORBIS__
	output.position = float4(input.vertex.x, -input.vertex.y, 1, 1);
#endif //! __ORBIS__
	output.uv = input.uv;

	return output;
}

float4 GameEditCopyShaderFP( GEFullscreenVertexOut input ) : FRAG_OUTPUT_COLOR
{
	float4 pixel = GEColorBuffer.Sample( GEColorBufferSampler, input.uv );
	return pixel;
}

#ifndef __ORBIS__

BlendState GameEditNoBlend 
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

DepthStencilState GameEditNoDepthState
{
	DepthEnable = FALSE;
	DepthWriteMask = Zero;
	DepthFunc = Always;
	StencilEnable = FALSE; 
};

RasterizerState GEDefaultRasterState 
{
	CullMode = None;
};

technique11 GameEditCopyBuffer
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GameEditCopyShaderVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GameEditCopyShaderFP() ) );

		SetDepthStencilState( GameEditNoDepthState, 0 );
		SetBlendState( GameEditNoBlend, float4(0,0,0,0), 0xFFFFffff );
		SetRasterizerState( GEDefaultRasterState );
	}
}

#endif

//////////////////////////////////////////////////////////

// For rendering a 2D texture.

Texture2D <float4> TextureSampler;

sampler GETexture2DLinearClampSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

struct GETexture2DInput
{
#ifndef __ORBIS__
	float3 Position		: POSITION;
#else
	float4 Position  	: POSITION;
#endif //! __ORBIS__
	float2 Uv			: TEXCOORD0;
};

struct GETexture2DOutput
{
	float4 Position		: SV_POSITION;
	float2 Uv			: TEXCOORD0;
};

BlendState GETexture2DNoBlend
{
	BlendEnable[0] = TRUE;
	RenderTargetWriteMask[0] = 15;
};


DepthStencilState GETexture2DDefaultDepthState
{
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Less_Equal;
	StencilEnable = FALSE;
};

RasterizerState GETexture2DDefaultRasterState
{
	CullMode = None;
};

GETexture2DOutput GERenderTextureVS(GETexture2DInput IN)
{
	GETexture2DOutput OUT;
	float3 position = IN.Position.xyz;
	OUT.Position = mul(float4(position, 1), WorldViewProjection);
	OUT.Uv = IN.Uv;

	return OUT;
}

float4 GERenderTextureFP(GETexture2DOutput IN) : FRAG_OUTPUT_COLOR0
{
	float4 texValue = TextureSampler.Sample(GETexture2DLinearClampSampler, IN.Uv);

	return texValue;
}

#ifndef __ORBIS__

technique11 GERenderTexture2D
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, GERenderTextureVS()));
		SetPixelShader(CompileShader(ps_4_0, GERenderTextureFP()));
	
		SetBlendState(GETexture2DNoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(GETexture2DDefaultDepthState, 0);
		SetRasterizerState(GETexture2DDefaultRasterState);
	}
}

#endif //! __ORBIS__

//////////////////////////////////////////////////////////

// For rendering a 3D texture.

Texture3D <float4> GETexture3D;

sampler GETexture3DSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
	AddressW = Clamp;
};

struct GETexture3DVPInput
{
	float4 Vertex	    : POSITION;
	float3 Uv			: TEXCOORD0;
};

struct GETexture3DVPOutput
{
	float4 Position		: SV_POSITION;
	float3 Uv			: TEXCOORD0;
};

GETexture3DVPOutput GERenderTexture3DVP(GETexture3DVPInput IN)
{
	GETexture3DVPOutput OUT;
	OUT.Position = mul(float4(IN.Vertex.xyz, 1.0f), WorldViewProjection);
	OUT.Uv = IN.Uv;
	return OUT;
}

float4 GERenderTexture3DFP(GETexture3DVPOutput IN) : FRAG_OUTPUT_COLOR
{
	return GETexture3D.Sample(GETexture3DSampler, IN.Uv);
}

technique11 GERenderTexture3D
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, GERenderTexture3DVP()));
		SetPixelShader(CompileShader(ps_4_0, GERenderTexture3DFP()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

//////////////////////////////////////////////////////////

// For rendering a cubemap texture.

TextureCube <float4> GECubemapTexture;

sampler GECubemapSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct GECubemapVPInput
{
#ifdef __ORBIS__
	float4 vertex		: POSITION;
#else //! __ORBIS__
	float3 vertex		: POSITION;
#endif //! __ORBIS__
};

struct GECubemapVPOutput
{
	float4 position		: SV_POSITION;
	float3 uv			: TEXCOORD0;
};

GECubemapVPOutput GERenderCubemapVP(GECubemapVPInput IN)
{
	GECubemapVPOutput OUT;
	OUT.position = mul(float4(IN.vertex.xyz, 1.0f), WorldViewProjection);
	OUT.uv = IN.vertex.xyz;
	return OUT;
}

float4 GERenderCubemapFP(GECubemapVPOutput IN) : FRAG_OUTPUT_COLOR
{
	return GECubemapTexture.SampleLevel(GECubemapSampler, IN.uv, 1.0f);
}

technique11 GERenderTextureCubemap
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = {"ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, GERenderCubemapVP()));
		SetPixelShader(CompileShader(ps_4_0, GERenderCubemapFP()));
		
		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);		
	}		
}

//////////////////////////////////////////////////////////

// For picking a terrain mesh instance

float4 TerrainPickingPs(TerrainRenderVsOutput In) : FRAG_OUTPUT_COLOR0
{
	return In.HeightmapPosition;
}

RasterizerState TerrainPickingDefaultRasterState
{
	CullMode = None;
};

technique11 TerrainPicking
<
	string PhyreRenderPass = "TerrainPicking";
	string VpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
	string FpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_5_0, TerrainRenderVs() ) );
		SetPixelShader( CompileShader( ps_5_0, TerrainPickingPs() ) );

		SetRasterizerState( TerrainPickingDefaultRasterState );
	}
}

//////////////////////////////////////////////////////////

// For rendering lightmap density

float2 LightmapDensityTextureSize = float2(1.0f, 1.0f);

struct LightmapInput
{
#ifdef __ORBIS__
	float4 Position		: POSITION;
#else //! __ORBIS__
	float3 Position		: POSITION;
#endif //! __ORBIS__
	float2 Uv			: TEXCOORD2;
};

struct LightmapOutput
{
	float4 Position		: SV_POSITION;
	float2 Uv			: TEXCOORD0;
};

LightmapOutput LightmapDensityVS(LightmapInput IN)
{
	LightmapOutput OUT;
	float3 position = IN.Position.xyz;
	OUT.Position = mul(float4(position, 1), WorldViewProjection);
	OUT.Uv = IN.Uv * LightmapDensityTextureSize;

	return OUT;
}

float4 LightmapDensityFP(LightmapOutput IN) : FRAG_OUTPUT_COLOR0
{
	uint x = uint(IN.Uv.x);
	uint y = uint(IN.Uv.y);

	float shade = ((x + y) & 0x1) ? 0.75f : 0.25f;
	return shade.xxxx;
}

#ifndef __ORBIS__

technique11 LightmapDensity
<
string VpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "INSTANCING_ENABLED"};
string FpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, LightmapDensityVS()));
		SetPixelShader(CompileShader(ps_4_0, LightmapDensityFP()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__

// For rendering lightmap only

Texture2D <float4> LightmapOnlyTexture;

LightmapOutput LightmapOnlyVS(LightmapInput IN)
{
	LightmapOutput OUT;
	float3 position = IN.Position.xyz;
	OUT.Position = mul(float4(position, 1), WorldViewProjection);
	OUT.Uv = IN.Uv;

	return OUT;
}

float4 LightmapOnlyFP(LightmapOutput IN) : FRAG_OUTPUT_COLOR0
{
	float4 texValue = LightmapOnlyTexture.Sample(LinearClampSampler, IN.Uv);
	return texValue.wwww;
}

#ifndef __ORBIS__

technique11 LightmapOnly
<
string VpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "INSTANCING_ENABLED"};
string FpIgnoreContextSwitches[] = { "ORTHO_CAMERA", "SKINNING_ENABLED", "INSTANCING_ENABLED"};
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, LightmapOnlyVS()));
		SetPixelShader(CompileShader(ps_4_0, LightmapOnlyFP()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__