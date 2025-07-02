//
//  CameraShaders.metal
//  QuantCap
//
//  Created by Владимир Костин on 26.09.2024.
//

#include <metal_stdlib>
using namespace metal;

kernel void cameraKernel(
						 texture2d<float, access::read_write> lumaTexture [[ texture(0) ]],
						 texture2d<float, access::read_write> chromaTexture [[ texture(1) ]],
						 constant uint& lutSize [[ buffer(0) ]],
						 device float4* lutData [[ buffer(1) ]],
						 uint2 gid [[ thread_position_in_grid ]]
						 ) {
	const float3x3 yCbCrToRGBMatrix = float3x3(
											   float3(1.164,  1.164, 1.164),
											   float3(0.0,   -0.392, 2.017),
											   float3(1.596, -0.813, 0.0)
											   );
	const float3x3 rgbToYCbCrMatrix = float3x3(
											   float3(0.257, -0.148,  0.439),
											   float3(0.504, -0.291, -0.368),
											   float3(0.098,  0.439, -0.071)
											   );
	
	float3 yuv;
	yuv.x = lumaTexture.read(gid).r * 255.0 - 16.0;
	yuv.yz = (chromaTexture.read(uint2(gid.x/2, gid.y/2)).rg - float2(0.5, 0.5)) * 255.0;
	
	float3 rgb = yCbCrToRGBMatrix * yuv / 255.0;
	rgb = clamp(rgb, 0.0, 1.0);
	
	if (lutSize > 2) {
		const float3 color = rgb * float(lutSize - 1);
		
		const uint minBI = floor(color.b) * lutSize * lutSize;
		const uint maxBI = ceil(color.b) * lutSize * lutSize;
		const uint minGI = floor(color.g) * lutSize;
		const uint maxGI = ceil(color.g) * lutSize;
		const uint minRI = floor(color.r);
		const uint maxRI = ceil(color.r);
		
		const float3 c000 = float3(lutData[minRI + minGI + minBI].rgb);
		const float3 c001 = float3(lutData[minRI + minGI + maxBI].rgb);
		const float3 c010 = float3(lutData[minRI + maxGI + minBI].rgb);
		const float3 c011 = float3(lutData[minRI + maxGI + maxBI].rgb);
		
		const float3 c100 = float3(lutData[maxRI + minGI + minBI].rgb);
		const float3 c101 = float3(lutData[maxRI + minGI + maxBI].rgb);
		const float3 c110 = float3(lutData[maxRI + maxGI + minBI].rgb);
		const float3 c111 = float3(lutData[maxRI + maxGI + maxBI].rgb);
		
		const float3 c00 = mix(c000, c100, fract(color.r));
		const float3 c01 = mix(c001, c101, fract(color.r));
		const float3 c10 = mix(c010, c110, fract(color.r));
		const float3 c11 = mix(c011, c111, fract(color.r));
		
		const float3 c0 = mix(c00, c10, fract(color.g));
		const float3 c1 = mix(c01, c11, fract(color.g));
		
		rgb = mix(c0, c1, fract(color.b));
	}
	
	float3 result = rgbToYCbCrMatrix * rgb;
	result.x = (result.x * 255.0 + 16.0) / 255.0;
	result.yz = (result.yz * 255.0 + 128.0) / 255.0;
	
	lumaTexture.write(float4(result.x, 0.0, 0.0, 1.0), gid);
	chromaTexture.write(float4(result.yz, 0.0, 1.0), uint2(gid.x/2, gid.y/2));
}
