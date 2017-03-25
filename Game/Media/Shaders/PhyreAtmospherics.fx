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

#define AVERAGE_GROUND_REFLECTANCE		0.1f
#define PI								3.14159265358979323846f
#define INV_PI							0.31830988618379067153f

#ifdef PHYRE_D3DFX
	#pragma warning (disable : 3571) // Disable pow(f, e) will not work for negative f, use abs(f) or conditionally handle negative values if you expect them
#endif // PHYRE_D3DFX

// SHADER VARS /////////////////////////////////////////////////////////////////////////////////
float InnerRadius;
float OuterRadius;
float InnerRadiusSq;
float OuterRadiusSq;

float Asymmetry;

float3 BetaR;
float3 BetaM;

// Atmospherics Parameter Resolutions:
// x - altitude
// y - view zenith
// z - sun zenith
// w - view-sun angle
float4 Resolutions;

float InverseHR;
float InverseHM;

float SunIntensity;
float3 SunDir;

// Fog parameters:
// x - Near
// y - Far
// z - (Far-Near)
// w - 1.0f/(Far-Near)
float4 FogParams;

// Sample amounts:
// x - transmittance samples
// y - scattering samples
// z - irradiance samples
// w - spherical integration samples
float4 NumSamples;

float FirstOrder;

RWTexture2D<float4> RWTransmittanceBuffer;			// TRANSMITTANCE
Texture2D<float4> TransmittanceBuffer;

RWTexture2D<float4> RWIrradianceBuffer;			// FINAL IRRADIANCE
Texture2D<float4> IrradianceBuffer;

RWTexture3D<float4> RWInscatterBuffer;			// FINAL INSCATTERING
Texture3D<float4> InscatterBuffer;

RWTexture2D<float4> RWDeltaIrradiance;		// DELTA-IRRADIANCE
Texture2D<float4> DeltaIrradiance;

RWTexture3D<float4> RWDeltaRadiance;				// DELTA-RADIANCE (Scattering around a sphere)
Texture3D<float4> DeltaRadiance;

RWTexture3D<float4> RWDeltaSR;				// DELTA-SCATTERING
Texture3D<float4> DeltaSR;
RWTexture3D<float4> RWDeltaSM;
Texture3D<float4> DeltaSM;

RWTexture2D<float4> RWIrradianceCopy;
RWTexture3D<float4> RWInscatterCopy;
Texture2D<float4> IrradianceCopy;
Texture3D<float4> InscatterCopy;

Texture2D <float4> ColorBuffer;
Texture2D <float4> DepthBuffer;

struct VertexIn
{
#ifdef __ORBIS__
	float4 vertex		:	POSITION;
#else
	float3 vertex		:	POSITION;
#endif
	float2 uv			:	TEXCOORD0;
};

struct VertexOut
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
	float3 ray			: TEXCOORD1;
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};

BlendState NoBlend
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

DepthStencilState DepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

// HELPER FUNCTIONS ////////////////////////////////////////////////////////////////////////////
float4 texture4D(Texture3D<float4> tex, float r, float mu, float muS, float nu)
{
	float rho = sqrt(r * r - InnerRadiusSq);
	float H = sqrt(OuterRadiusSq - InnerRadiusSq);

	float4 invRes = rcp(Resolutions);

	float rmu = r * mu;
	float delta = (rmu * rmu) - (r * r) + InnerRadiusSq;
	float4 cst = (rmu < 0.0f) && (delta > 0.0f) ? float4(1.0f, 0.0f, 0.0f, 0.5f - 0.5f * invRes.y) : float4(-1.0f, H * H, H, 0.5f + 0.5f * invRes.y);
	const float uMuSDenom = rcp(1.0f - exp(-3.6f));

	float3 coords = float3(0, 0, 0);
	coords.z = (0.5f * invRes.x) + (rho / H * (1.0f - invRes.x));
	coords.y = cst.w + ((rmu * cst.x + sqrt(delta + cst.y)) / ((rho + cst.z) * (0.5f - invRes.y)));
	coords.x = (0.5f * invRes.z) + max((1.0f - exp(-3.0f * muS - 0.6f)) * uMuSDenom, 0.0) * (1.0 - invRes.z);
	
	// Interpolate between the two lookups
	float linearInterp = (nu + 1.0f) / 2.0f * (Resolutions.w - 1.0f);
	float uNu = floor(linearInterp);
	linearInterp = frac(linearInterp);
	coords.x += uNu;

	float4 val1 = tex.SampleLevel(LinearClampSampler, float3(coords.x * invRes.w, coords.yz), 0);
	float4 val2 = tex.SampleLevel(LinearClampSampler, float3(coords.x * invRes.w + invRes.w, coords.yz), 0);
	return lerp(val1, val2, linearInterp);
}

float ConvertDepth( float depth )
{
	return -( cameraNearTimesFar / ( depth * cameraFarMinusNear - cameraNearFar.y ) );
}

void GetTransmittanceRMu( in float2 uv, out float r, out float mu )
{
	r = InnerRadius + ( uv.y * uv.y ) * ( OuterRadius - InnerRadius );
	mu = -0.15f + tan( 1.5f * uv.x ) / tan( 1.5f ) * ( 1.0f + 0.15f );
}

float2 GetTransmittanceUV( float r, float mu )
{
	float2 uv;
	uv.y = sqrt( ( r - InnerRadius ) / ( OuterRadius - InnerRadius ) );
	uv.x = atan( ( mu + 0.15f ) / ( 1.0f + 0.15f ) * tan( 1.5f ) ) / 1.5f;

	return uv;
}

void GetIrradianceRMuS( in float2 uv, out float r, out float muS )
{
	r = InnerRadius + ( uv.y * ( OuterRadius - InnerRadius ) );
	muS = -0.2f + ( uv.x * ( 1.0f + 0.2f ) );
}

float2 GetIrradianceUV( float r, float muS )
{
	float2 uv;
	uv.x = ( muS + 0.2f ) / ( 1.0f + 0.2f );
	uv.y = ( r - InnerRadius ) / ( OuterRadius - InnerRadius );

	return uv;
}

void GetAngles( in float2 coords, in float alt, in float4 dhdH, out float viewZenith, out float sunZenith, out float viewSunAngle )
{
	if( coords.y < Resolutions.y / 2.0f )
	{
		float d = 1.0f - coords.y / ( Resolutions.y / 2.0f - 1.0f );
		d = min( max( dhdH.z, d * dhdH.w ), dhdH.w * 0.999f );
		viewZenith = ( InnerRadiusSq - ( alt * alt ) - ( d * d ) ) / ( 2.0f * alt * d );
		viewZenith = min( viewZenith, -sqrt( 1.0f - ( InnerRadiusSq / ( alt * alt ) ) ) - 0.001f );
	}
	else
	{
		float d = ( coords.y - Resolutions.y / 2.0f ) / ( Resolutions.y / 2.0f - 1.0f );
		d = min( max( dhdH.x, d * dhdH.y ), dhdH.y * 0.999f );
		viewZenith = ( OuterRadiusSq - ( alt * alt ) - ( d * d ) ) / ( 2.0f * alt * d );
	}

	sunZenith = fmod( coords.x, Resolutions.z ) / ( Resolutions.z - 1.0f );
	sunZenith = tan( ( 2.0f * sunZenith - 1.0f + 0.26f ) * 1.1f ) / tan( 1.26f * 1.1f );
	viewSunAngle = -1.0f + floor( coords.x / Resolutions.z ) / ( Resolutions.w - 1.0f ) * 2.0f;
}

void GetRMuMuSNu( in uint3 coords, out float alt, out float viewZenith, out float sunZenith, out float viewSunAngle )
{
	float2 angleCoords = ( float2 )coords.xy;
	

	// Calculate alt
	alt = coords.z / ( Resolutions.x - 1.0f );
	alt = alt * alt;
	alt = sqrt( InnerRadiusSq + alt * ( OuterRadiusSq - InnerRadiusSq ) ) + ( coords.z == 0 ? 0.01f : ( (int)coords.z == (int)(Resolutions.x - 1) ? -0.001f : 0.0f ) );

	// Calculate the dhdH value for use in non-linear mapping of angles
	float4 dhdH;
	dhdH.x = OuterRadius - alt;
	dhdH.y = sqrt( alt * alt - InnerRadiusSq ) + sqrt( OuterRadiusSq - InnerRadiusSq );
	dhdH.z = alt - InnerRadius;
	dhdH.w = sqrt( alt * alt - InnerRadiusSq );

	// Calculate the angles
	GetAngles( angleCoords, alt, dhdH, viewZenith, sunZenith, viewSunAngle );
}

void GetViewAndSunVector( in float mu, in float muS, in float nu, out float3 v, out float3 s )
{
	v = float3(sqrt(1.0 - mu * mu), 0.0, mu);
    float sx = v.x == 0.0 ? 0.0 : (nu - muS * mu) / v.x;
    s = float3(sx, sqrt(max(0.0, 1.0 - sx * sx - muS * muS)), muS);
}

float PhaseR( float cosTheta )
{
	return ( 3.0f / ( 16.0f * PI ) ) * ( 1.0f + cosTheta * cosTheta );
}

float PhaseM(float cosTheta, float g)
{
	float g2 = g * g;
	float cosTheta2 = cosTheta * cosTheta;

	return 0.375f * INV_PI * (1.0f - g2) * pow(1.0f + g2 - (2.0f * g * cosTheta), -1.5f) * (1.0f + cosTheta2) / (2.0f + g2);
}

float RaySphereIntersect( float3 P, float3 v, float d )
{
	float b = 2.0f * dot(P,v);
	float c = dot(P,P) - d*d;

	float discriminant = (b * b) - (4.0 * c);

	float disc_rt = sqrt(discriminant);
	float t1 = (-b + disc_rt)*0.5f; 
	float t2 = (-b - disc_rt)*0.5f;
	
	return min(t1, t2);
}

float Density( in float alt, in float invScaleHeight )
{
	return exp( -( alt - InnerRadius ) * invScaleHeight );
}

float3 Transmittance( float r, float mu )
{
	float2 uv = GetTransmittanceUV( r, mu );
	return TransmittanceBuffer.SampleLevel( LinearClampSampler, uv, 0 ).rgb;
}

float3 Transmittance( float r, float mu, float d )
{
	float3 result;
	float r1 = sqrt(r * r + d * d + 2.0 * r * mu * d);
    float mu1 = (r * mu + d) / r1;
    if (mu > 0.0) {
        result = min(Transmittance(r, mu) / Transmittance(r1, mu1), 1.0);
    } else {
        result = min(Transmittance(r1, -mu1) / Transmittance(r, -mu), 1.0);
    }
    return result;
}

float3 TransmittanceWithShadow( float r, float mu )
{
	return mu < -sqrt( 1.0f - ( InnerRadiusSq / ( r * r ) ) ) ? float3( 0.0f, 0.0f, 0.0f ) : Transmittance( r, mu );
}

float3 Irradiance( Texture2D<float4> irradianceTex, float r, float muS )
{
	float2 uv = GetIrradianceUV( r, muS );
	return irradianceTex.SampleLevel( LinearClampSampler, uv, 0 ).rgb;
}

float Limit( float altitude, float mu )
{
	float RL = OuterRadius + 1.0f;
	float dout = -altitude * mu + sqrt( altitude * altitude * ( mu * mu - 1.0f ) + RL * RL );
	float delta2 = altitude * altitude * ( mu * mu - 1.0f ) + InnerRadiusSq;
	if( delta2 >= 0.0f )
	{
		float din = -altitude * mu - sqrt( delta2 );
		if( din >= 0.0f )
		{
			dout = min(dout, din);
		}
	}

	return dout;
}

void Integrand( in float alt, in float mu, in float muS, in float nu, in float dist, out float3 ray, out float3 mie )
{
	ray = float3( 0.0f, 0.0f, 0.0f );
	mie = float3( 0.0f, 0.0f, 0.0f );

	float alt_i = sqrt( ( alt * alt ) + ( dist * dist ) + ( 2.0f * alt * mu * dist ) );
	float muS_i = ( nu * dist + muS * alt ) / alt_i;

	alt_i = max( InnerRadius, alt_i );

	float horizon = -sqrt( 1.0f - ( InnerRadiusSq / ( alt_i * alt_i ) ) );
	if( muS_i >= horizon )
	{
		float3 t = Transmittance( alt, mu, dist ) * Transmittance( alt_i, muS_i );		// exp( -t( PPc ) - t( PaP ) )
		ray = exp( -( alt_i - InnerRadius ) * InverseHR ) * t;
		mie = exp( -( alt_i - InnerRadius ) * InverseHM ) * t;
	}
}

float3 IntegrandInscattering( in float alt, in float viewZenith, in float sunZenith, in float viewSunAngle, in float d )
{
	float alt_i = sqrt( alt * alt + d * d + 2.0f * alt * viewZenith * d );
	float mu_i = ( alt * viewZenith + d ) / alt_i;
	float mus_i = ( viewSunAngle * d + sunZenith * alt ) / alt_i;

	return texture4D( DeltaRadiance, alt_i, mu_i, mus_i, viewSunAngle ).rgb * Transmittance( alt, viewZenith, d );
}

float OpticalDepth( in float invScaleHeight, in float alt, in float viewZenith )
{
	float cosHorizon = -sqrt( 1.0f - ( InnerRadiusSq / ( alt * alt ) ) );

	float opticalDepth = 0.0f;
	float dx = Limit( alt, viewZenith ) / NumSamples.x;

	float initialDensity = Density( alt, invScaleHeight );

	for( int i = 1; i <= int(NumSamples.x); ++i )
	{
		float x = ( (float)i ) * dx;
		float alt_i = sqrt( ( alt * alt ) + ( x * x ) + ( 2.0f * x * alt * viewZenith ) );

		float currentDensity = Density( alt_i, invScaleHeight );

		opticalDepth += ( initialDensity + currentDensity ) / 2.0f * dx;
		initialDensity = currentDensity;
	}

	return ( viewZenith < cosHorizon ) ? 1e9 : opticalDepth;
}

float3 GetMie( float4 raymie )
{
	return raymie.rgb * ( raymie.w / max( raymie.r, 1e-4 ) ) * ( BetaR.r / BetaR );
}

static const float gammaCorrectInv = 1.0f / 2.2f;
#define EXPOSURE	2.0f

float3 HDR( float3 L )
{
	float3 result;

	L *= EXPOSURE;

	// Reinhard
	L = L / ( 1 + L );
	result = pow( L, gammaCorrectInv );

	return result;
}

// SHADERS /////////////////////////////////////////////////////////////////////////////////////
[numthreads( 4, 4, 1 )]
void CSPrecomputeTransmittance( uint2 DTid : SV_DispatchThreadID )
{
	uint2 dim;
	RWTransmittanceBuffer.GetDimensions( dim.x, dim.y );

	// The dispatch thread ID gives us the value for the View Zenith (x) and altitude (y)
	float2 id = ( float2 )DTid.xy + float2( 0.5f, 0.5f );
	float2 uv = id / float2( dim.x, dim.y );
	float alt;
	float viewZenith;
	GetTransmittanceRMu( uv, alt, viewZenith );

	// Optical depth values for Rayleigh (x) and Mie (y)
	float2 opticalDepth = float2( OpticalDepth( InverseHR, alt, viewZenith ),
								  OpticalDepth( InverseHM, alt, viewZenith ) );

	// Multiply optical depth by the extinction coeffs for Rayleigh and Mie
	// Note: BetaREx = BetaR and BetaMEx approx 1.1 * BetaM
	float3 BetaMEx = BetaM / 0.9f;
	float3 finalDepth = ( BetaR * opticalDepth.x ) + ( BetaMEx * opticalDepth.y );

	// Write it out
	float4 col = float4( exp(-finalDepth), 0.0f );
	RWTransmittanceBuffer[DTid.xy] = col;
}

[numthreads( 4, 4, 1 )]
void CSPrecomputeSingleIrradiance( uint2 DTid : SV_DispatchThreadID )
{
	uint2 dim;
	RWDeltaIrradiance.GetDimensions( dim.x, dim.y );

	// Get altitude and sun zenith
	float2 id = float2( DTid.xy );
	float2 uv = id / float2( dim.x - 1, dim.y - 1 );
	float alt, sunZenith;
	GetIrradianceRMuS( uv, alt, sunZenith );

	float3 attenuation = Transmittance( alt, sunZenith );
	RWDeltaIrradiance[DTid.xy] = float4( attenuation * max( sunZenith, 0.0f ), 0.0f );
}

[numthreads( 4, 4, 4 )]
void CSPrecomputeSingleScattering( uint3 DTid : SV_DispatchThreadID )
{
	uint3 dim;
	RWDeltaSR.GetDimensions( dim.x, dim.y, dim.z );

	float alt, viewZenith, sunZenith, viewSunAngle;
	GetRMuMuSNu( DTid, alt, viewZenith, sunZenith, viewSunAngle );

	float3 testColor = float3( viewZenith, sunZenith, viewSunAngle );
	testColor *= 0.5f;
	testColor += float3( 0.5f, 0.5f, 0.5f );

	float3 rayleighColor = float3( 0.0f, 0.0f, 0.0f );
	float3 mieColor = float3( 0.0f, 0.0f, 0.0f );

	float3 rayleighIntegrand = float3( 0.0f, 0.0f, 0.0f );
	float3 mieIntegrand = float3( 0.0f, 0.0f, 0.0f );

	float dx = Limit( alt, viewZenith ) / NumSamples.y;
	float d = 0.0f;

	float3 rayi, miei;
	Integrand( alt, viewZenith, sunZenith, viewSunAngle, d, rayi, miei );

	for( uint i = 1; i <= uint(NumSamples.y); ++i )
	{
		d = ( (float)i ) * dx;
		float3 rayj, miej;
		Integrand( alt, viewZenith, sunZenith, viewSunAngle, d, rayj, miej );
		rayleighIntegrand += ( rayi + rayj ) / 2.0f * dx;			// Average the rayleigh/mie values
		mieIntegrand += ( miei + miej ) / 2.0f * dx;				// and multiply by the sample distance
		rayi = rayj;
		miei = miej;
	}

	rayleighColor = rayleighIntegrand * BetaR;
	mieColor = mieIntegrand * BetaM;

	// Populate the Delta-S tables without phase functions (gets reintroduced in the multiple scattering pass)
	RWDeltaSR[DTid.xyz] = float4( rayleighColor, 0.0f );
	RWDeltaSM[DTid.xyz] = float4( mieColor, 0.0f );
}

[numthreads( 4, 4, 4 )]
void CSInitInscattering( uint3 DTid : SV_DispatchThreadID )
{
	RWInscatterBuffer[DTid.xyz] = float4( DeltaSR[DTid.xyz].rgb, DeltaSM[DTid.xyz].r );
}

[numthreads( 4, 4, 4 )]
void CSPrecomputeRadiance( uint3 DTid : SV_DispatchThreadID )
{
	uint3 dim;
	RWDeltaRadiance.GetDimensions( dim.x, dim.y, dim.z );

	float alt, viewZenith, sunZenith, viewSunAngle;
	GetRMuMuSNu( DTid, alt, viewZenith, sunZenith, viewSunAngle );

	// Clamp vars
	alt = clamp( alt, InnerRadius, OuterRadius );
	viewZenith = clamp( viewZenith, -1.0f, 1.0f );
	sunZenith = clamp( sunZenith, -1.0f, 1.0f );
	float var = sqrt( 1.0f - viewZenith * viewZenith ) * sqrt( 1.0f - sunZenith * sunZenith );
	viewSunAngle = clamp( viewSunAngle, sunZenith * viewZenith - var, sunZenith * viewZenith + var );

	float dtheta = PI / NumSamples.w;
	float dphi =  ( 2.0f * PI ) / NumSamples.w;

	float cosHorizon = -sqrt( 1.0f - ( InnerRadiusSq / ( alt * alt ) ) );
	float3 v, s;
	GetViewAndSunVector( viewZenith, sunZenith, viewSunAngle, v, s );

	float3 rayCoeff = BetaR * Density(alt, InverseHR);
	float3 mieCoeff = BetaM * Density(alt, InverseHM);

	float3 raymie = float3(0.0f, 0.0f, 0.0f);

	// Integrate about a sphere for each sample point
	for( uint itheta = 0; itheta < uint(NumSamples.w); ++itheta )
	{
		float theta = ( float( itheta ) + 0.5f ) * dtheta;
		float cosTheta = cos( theta );

		float greflectance = 0.0f;
		float dground = 0.0f;
		float3 gtransp = float3( 0.0f, 0.0f, 0.0f );

		// If the ground is visible calculate the distance and transparency
		// to the surface point
		if( cosTheta < cosHorizon )
		{
			greflectance = AVERAGE_GROUND_REFLECTANCE * INV_PI;
			dground = -alt * cosTheta - sqrt( alt * alt * ( cosTheta * cosTheta - 1.0f ) + InnerRadiusSq );
			gtransp = Transmittance( alt, -( alt * cosTheta + dground ), dground );
		}

		for( uint iphi = 0; iphi < uint(NumSamples.w); ++iphi )
		{
			float phi = (float(iphi) + 0.5f) * (dphi);
			float3 w = float3( cos( phi ) * sin( theta ), sin( phi ) * sin( theta ), cosTheta );

			float nu1 = dot( s, w );
			float nu2 = dot( v, w );
			float pr2 = PhaseR( nu2 );
			float pm2 = PhaseM( nu2, Asymmetry );

			// Compute irradiance
			float3 gnormal = ( float3( 0.0f, 0.0f, alt ) + dground * w ) / InnerRadius;
			float3 girradiance = Irradiance( DeltaIrradiance, InnerRadius, dot( gnormal, s ) );

			// Incident light to current position from direction w
			float3 raymie1 = greflectance * girradiance * gtransp;

			// Add inscattered light
			if( FirstOrder == 1.0f )
			{
				// reintroduce the phase functions here
				float pr1 = PhaseR( nu1 );
				float pm1 = PhaseM( nu1, Asymmetry );
				float3 ray1 = texture4D( DeltaSR, alt, w.z, sunZenith, nu1 ).rgb;
				float3 mie1 = texture4D( DeltaSM, alt, w.z, sunZenith, nu1 ).rgb;

				raymie1 += ray1 * pr1 + mie1 * pm1;
			}
			else
			{
				raymie1 += texture4D( DeltaSR, alt, w.z, sunZenith, nu1 ).rgb;
			}

			// Add to the final light contribution
			float dw = dtheta * dphi * sin( theta );
			raymie += raymie1 * ( rayCoeff * pr2 + mieCoeff * pm2 ) * dw;
		}
	}

	RWDeltaRadiance[DTid.xyz] = float4( raymie, 0.0f );
}

[numthreads(4, 4, 1)]
void CSPrecomputeMultipleIrradiance( uint2 DTid : SV_DispatchThreadID )
{
	uint2 dim;
	RWDeltaIrradiance.GetDimensions( dim.x, dim.y );

	// Get altitude and sun zenith
	float alt, sunZenith;
	float2 id = float2( DTid.xy );// +float2( 0.5f, 0.5f );
	float2 coords = id / float2( dim.x, dim.y );
	GetIrradianceRMuS( coords, alt, sunZenith );

	// Calculate the sun vector from the sunZenith
	float3 s = float3( max( sqrt( 1.0f - sunZenith * sunZenith ), 0.0f ), 0.0f, sunZenith );

	float dtheta = PI / NumSamples.z;
	float dphi = PI / NumSamples.z;

	float3 color = float3( 0.0f, 0.0f, 0.0f );

	for( uint iphi = 0; iphi < 2 * uint(NumSamples.z); ++iphi )
	{
		float phi = ( float( iphi ) + 0.5f ) * dphi;

		for( uint itheta = 0; itheta < uint(NumSamples.z) / 2; ++itheta )	// divided by 2 because irradiance acts on the HEMIsphere, NOT the SPHERE
		{
			float theta = ( float( itheta ) + 0.5f ) * dtheta;
			float3 w = float3( cos( phi ) * sin( theta ), sin( phi ) * sin( theta ), cos( theta ) );
			float nu = dot( s, w );
			float dw = dtheta * dphi * sin( theta );

			if( FirstOrder == 1.0f )
			{
				// Reintroduce phase functions
				float pr = PhaseR( nu );
				float pm = PhaseM( nu, Asymmetry );
				float3 ray = texture4D( DeltaSR, alt, w.z, sunZenith, nu ).rgb * pr;
				float3 mie = texture4D( DeltaSM, alt, w.z, sunZenith, nu ).rgb * pm;

				color += ( ray + mie ) * w.z * dw;
			}
			else
			{
				color += texture4D( DeltaSR, alt, w.z, sunZenith, nu ).rgb * w.z * dw;
			}
		}
	}

	RWDeltaIrradiance[DTid.xy] = float4( color, 0.0f );
}

[numthreads( 4, 4, 4 )]
void CSPrecomputeMultipleScattering( uint3 DTid : SV_DispatchThreadID )
{
	uint3 dim;
	RWDeltaSR.GetDimensions( dim.x, dim.y, dim.z );

	float alt, viewZenith, sunZenith, viewSunAngle;
	GetRMuMuSNu( DTid, alt, viewZenith, sunZenith, viewSunAngle );

	float3 raymie = float3( 0.0f, 0.0f, 0.0f );
	float dx = Limit( alt, viewZenith ) / NumSamples.y;
	float d = 0.0f;

	float3 raymie1 = IntegrandInscattering( alt, viewZenith, sunZenith, viewSunAngle, d );

	for( uint i = 1; i <= uint(NumSamples.y); ++i )
	{
		d = ( (float)i ) * dx;
		float3 raymie2 = IntegrandInscattering( alt, viewZenith, sunZenith, viewSunAngle, d );
		raymie += ( raymie1 + raymie2 ) / 2.0f * dx;
		raymie1 = raymie2;
	}

	RWDeltaSR[DTid.xyz] = float4( raymie, 0.0f );
}

[numthreads( 4, 4, 1 )]
void CSCopyIrradiance( uint3 DTid : SV_DispatchThreadID )
{
	RWIrradianceCopy[DTid.xy] = ( FirstOrder == 1.0f ) ? float4(0,0,0,0) : IrradianceBuffer[DTid.xy];
}

[numthreads( 4, 4, 4 )]
void CSCopyInscatter( uint3 DTid : SV_DispatchThreadID )
{
	RWInscatterCopy[DTid] = InscatterBuffer[DTid];
}

[numthreads( 4, 4, 1 )]
void CSSumIrradiance( uint2 DTid : SV_DispatchThreadID )
{
	uint2 dim;
	RWIrradianceBuffer.GetDimensions( dim.x, dim.y );

	float2 uv = DTid.xy / float2( dim );
	float4 color = DeltaIrradiance.SampleLevel( LinearClampSampler, uv, 0 );
	float4 currentColor = IrradianceCopy.SampleLevel( LinearClampSampler, uv, 0 );

	RWIrradianceBuffer[DTid.xy] = ( currentColor + float4( color.rgb, 0.0f ) );
}

[numthreads( 4, 4, 4 )]
void CSSumInscatter( uint3 DTid : SV_DispatchThreadID )
{
	uint3 dim;
	RWInscatterBuffer.GetDimensions( dim.x, dim.y, dim.z );

	float alt, viewZenith, sunZenith, viewSunAngle;
	GetRMuMuSNu( DTid, alt, viewZenith, sunZenith, viewSunAngle );

	float invPhaseR = PhaseR( viewSunAngle );

	float3 id = float3( DTid.xyz );
	float3 inscatterTexCoords = float3( id / float3( Resolutions.z * Resolutions.w, Resolutions.y, Resolutions.x ) );

	float4 color = DeltaSR.SampleLevel( LinearClampSampler, inscatterTexCoords, 0 );
	float4 currentColor = InscatterCopy[DTid.xyz];

	RWInscatterBuffer[DTid.xyz] = currentColor + float4( color.rgb / PhaseR( viewSunAngle ), 0.0f );
}

[numthreads( 4, 4, 4 )]
void CSResetTextures(uint3 DTid : SV_DispatchThreadID)
{
	// Reset irradiance and inscatter buffers and copy buffers
	uint2 irrDim;
	RWIrradianceBuffer.GetDimensions(irrDim.x, irrDim.y);

	if((DTid.x < irrDim.x) && (DTid.y < irrDim.y) && (DTid.z == 0))
	{
		RWIrradianceBuffer[DTid.xy] = float4(0, 0, 0, 0);
		RWIrradianceCopy[DTid.xy] = float4(0, 0, 0, 0);
	}

	RWInscatterBuffer[DTid.xyz] = float4(0, 0, 0, 0);
	RWInscatterCopy[DTid.xyz] = float4(0, 0, 0, 0);
}

// RENDERING SHADER
float3 Inscatter( inout float3 x, inout float t, in float3 v, in float3 s, inout float2 rMu, inout float3 attenuation )
{
	float3 result = float3( 0.0f, 0.0f, 0.0f );

	float d = -rMu.x * rMu.y - sqrt( rMu.x * rMu.x * ( rMu.y * rMu.y - 1.0f ) + OuterRadiusSq );
	if( d > 0.0f )
	{
		x += d * v;
		t -= d;
		rMu.y = ( rMu.x * rMu.y * d ) / OuterRadius;
		rMu.x = OuterRadius;
	}

	if( rMu.x <= OuterRadius )
	{
		float nu = dot( v, s );
		float muS = dot( x, s ) / rMu.x;
		float pr = PhaseR( nu );
		float pm = PhaseM( nu, Asymmetry );

		float4 inscatter = max( texture4D( InscatterBuffer, rMu.x, rMu.y, muS, nu ), 0.0f );
		if( t > 0.0f )
		{
			float3 x0 = x + t * v;
			float r0 = length( x0 );
			float mu0 = dot( x0, v ) / r0;
			float muS0 = dot( x0, s ) / r0;

			attenuation = Transmittance( rMu.x, rMu.y, t );

			if( r0 > InnerRadius + 0.01f )
			{
				inscatter = max( inscatter - attenuation.rgbr * texture4D( InscatterBuffer, r0, mu0, muS0, nu ), 0.0f );

				// Avoids imprecision problems near horizon
				const float EPS = 0.004f;
				float horizon = -sqrt( 1.0f - ( InnerRadiusSq / ( rMu.x * rMu.x ) ) );
				if( abs( rMu.y - horizon ) < EPS )
				{
					float a = ( ( rMu.y - horizon ) + EPS ) / ( 2.0f * EPS );
					rMu.y = horizon - EPS;
					r0 = sqrt( rMu.x * rMu.x + t * t + 2.0f * rMu.x * t * rMu.y );
					mu0 = ( rMu.x * rMu.y + t ) / r0;

					float4 inscatter0 = texture4D( InscatterBuffer, rMu.x, rMu.y, muS, nu );
					float4 inscatter1 = texture4D( InscatterBuffer, r0, mu0, muS0, nu );
					float4 inscatterA = max( inscatter0 - attenuation.rgbr * inscatter1, 0.0f );

					rMu.y = horizon + EPS;
					r0 = sqrt( rMu.x * rMu.x + t * t + 2.0f * rMu.x * t * rMu.y );
					mu0 = ( rMu.x * rMu.y + t ) / r0;
					inscatter0 = texture4D( InscatterBuffer, rMu.x, rMu.y, muS, nu );
					inscatter1 = texture4D( InscatterBuffer, r0, mu0, muS0, nu );
					float4 inscatterB = max( inscatter0 - attenuation.rgbr * inscatter1, 0.0f );

					inscatter = lerp( inscatterA, inscatterB, a );
				}
			}
		}

		inscatter.w *= smoothstep( 0.00f, 0.02f, muS );
		result = max( inscatter.rgb * pr + GetMie( inscatter ) * pm, 0.0f );
	}

	return result * SunIntensity;
}

float3 GroundColor( float3 x, float t, float3 v, float3 s, float3 attenuation )
{
	float3 result = float3( 0.0f, 0.0f, 0.0f );

	if( t > 0.0f )
	{
		float3 x0 = x + t * v;
		float r0 = length( x0 );
		float3 n = x0 / r0;
		float2 coords = float2( atan2( n.y, n.x ), acos( n.z ) ) * float2( 0.5f, 1.0f ) * INV_PI + float2( 0.5f, 0.0f );
		float4 reflectance = ColorBuffer.Sample( LinearClampSampler, coords ) * float4( 0.2f, 0.2f, 0.2f, 1.0f );

		if( r0 > InnerRadius + 0.01f )
		{
			reflectance = float4( 0.4f, 0.4f, 0.4f, 0.0f );
		}

		float muS = dot( n, s );
		float3 sunLight = TransmittanceWithShadow( r0, muS );

		float3 groundSkyLight = Irradiance( IrradianceBuffer, r0, muS );
		float3 groundColor = reflectance.rgb * ( max( muS, 0.0f ) * sunLight + groundSkyLight ) * SunIntensity * INV_PI;

		result = attenuation * groundColor;
	}

	return result;
}

VertexOut AtmosVS(VertexIn input)
{
	VertexOut output;
	output.position = float4( input.vertex.xy, 1, 1 );
	float2 uv = input.uv;

#ifndef __ORBIS__
		uv.y = 1.0f - input.uv.y;
#endif //! __ORBIS__

	output.uv = uv;
	output.ray = mul( float4( mul( output.position, ProjInverse ).xyz, 0.0f ), ViewInverse ).xyz;

	return output;
}

float4 AtmosPS(VertexOut input) : FRAG_OUTPUT_COLOR
{
	float3 x = EyePosition;
	float3 v = normalize(input.ray);
	float3 s = normalize(SunDir);
	float timeVal = time * 0.5f;

	float2 rMu = float2( length( x ), dot( x, v ) / length( x ) );

	rMu.y = rMu.y * 0.5f + 0.5f;
	float t = -rMu.x * rMu.y - sqrt( rMu.x * rMu.x * ( rMu.y * rMu.y - 1.0f ) + InnerRadiusSq );

	float offset = 10.0f;
	float3 g = x - float3( 0.0f, 0.0f, InnerRadius + offset );
	float a = v.x * v.x + v.y * v.y - v.z * v.z;
	float b = 2.0f * ( g.x * v.x + g.y * v.y - g.z * v.z );
	float c = g.x * g.x + g.y * g.y - g.z * g.z;
	float d = -( b + sqrt( b * b - 4.0f * a * c ) ) / ( 2.0f * a );
	bool cone = d > 0.0f && abs( x.z + d * v.z - InnerRadius ) <= offset;

	if( t > 0.0f )
	{
		if( cone && d < t )
		{
			t = d;
		}
	}
	else if( cone )
	{
		t = d;
	}

	float3 attenuation = float3(1.0f, 1.0f, 1.0f);
	float3 inscatter = float3(0.0f, 0.0f, 0.0f);
	float3 groundColor = float3(0.0f, 0.0f, 0.0f);

	inscatter = Inscatter( x, t, v, s, rMu, attenuation );
	groundColor = GroundColor( x, t, v, s, attenuation );

	float4 fogColor = float4( HDR( groundColor + inscatter ), 1.0f );
	float4 color = ColorBuffer.Sample( LinearClampSampler, input.uv );
	float depth = ConvertDepth( DepthBuffer.Sample( PointClampSampler, input.uv ).r );
	float fogAmt = saturate( ( abs( depth ) - FogParams.x ) * FogParams.w );

	return lerp( color, fogColor, fogAmt );
}

float4 AtmosTexturesPS(VertexOut input) : FRAG_OUTPUT_COLOR
{
	float2 uv = input.uv;
#ifdef __ORBIS__
	uv.y = 1.0f - uv.y;
#endif //! __ORBIS__
	uint2 transmittanceDim, irradianceDim;
	uint3 inscatterDim;
	TransmittanceBuffer.GetDimensions( transmittanceDim.x, transmittanceDim.y );
	IrradianceBuffer.GetDimensions( irradianceDim.x, irradianceDim.y );
	InscatterBuffer.GetDimensions( inscatterDim.x, inscatterDim.y, inscatterDim.z );
	
	float3 color = float3(0,0,0);

	if(uv.y < 0.25f)
	{
		uv.y *= 4.0f;
		color = TransmittanceBuffer.Sample( LinearClampSampler, uv ).xyz;
	}
	else if( uv.y < 0.50f )
	{
		uv.y -= 0.25f;
		uv.y *= 4.0f;
		color = IrradianceBuffer.Sample( LinearClampSampler, uv ).xyz * 50.0f;
	}
	else if( uv.y < 0.75f )
	{
		uv.y -= 0.5f;
		uv.y *= 4.0f;
		float z = uv.x * 0.5f;
		uv.x *= 16.0f;
		uv.x = frac(uv.x);
		color = InscatterBuffer.Sample( LinearClampSampler, float3( uv.xy, z ) ).xyz;
	}
	else
	{
		uv.y -= 0.75f;
		uv.y *= 4.0f;
		float z = uv.x * 0.5f + 0.5f;
		uv.x *= 16.0f;
		uv.x = frac(uv.x);
		color = InscatterBuffer.Sample( LinearClampSampler, float3( uv.xy, z ) ).xyz;
	}

	float a = 0.0055f;
	float b = 0.0065f;
	color *= smoothstep( a, b, abs( input.uv.y - 0.25f ) );
	color *= smoothstep( a, b, abs( input.uv.y - 0.5f ) );
	color *= smoothstep( a, b, abs( input.uv.y - 0.75f ) );

	return float4( color, 1.0f );
}

#ifndef __ORBIS__
// TECHNIQUES //////////////////////////////////////////////////////////////////////////////////
technique11 PrecomputeTransmittance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSPrecomputeTransmittance() ) );
	}
}

technique11 PrecomputeSingleIrradiance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSPrecomputeSingleIrradiance() ) );
	}
}

technique11 PrecomputeSingleScattering
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSPrecomputeSingleScattering() ) );
	}
}

technique11 InitialiseInscattering
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSInitInscattering() ) );
	}
}

technique11 PrecomputeRadiance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSPrecomputeRadiance() ) );
	}
}

technique11 PrecomputeMultipleIrradiance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSPrecomputeMultipleIrradiance() ) );
	}
}

technique11 PrecomputeMultipleScattering
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSPrecomputeMultipleScattering() ) );
	}
}

technique11 CopyIrradiance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSCopyIrradiance() ) );
	}
}

technique11 CopyInscatter
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSCopyInscatter() ) );
	}
}

technique11 AddToIrradiance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSSumIrradiance() ) );
	}
}

technique11 AddToInscatter
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CSSumInscatter() ) );
	}
}

technique11 ResetTextures
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CSResetTextures()));
	}
}

technique11 RenderAtmosphere
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, AtmosVS() ) );
		SetPixelShader( CompileShader( ps_5_0, AtmosPS() ) );

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderTextures
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, AtmosVS() ) );
		SetPixelShader( CompileShader( ps_5_0, AtmosTexturesPS() ) );

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__