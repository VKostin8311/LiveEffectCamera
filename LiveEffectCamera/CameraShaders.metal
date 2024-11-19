//
//  CameraShaders.metal
//  QuantCap
//
//  Created by Владимир Костин on 26.09.2024.
//

#include <metal_stdlib>
using namespace metal;

float gaussian(float x, float y, float sigma) {
    const float gaussianExponent = -(pow(x, 2.0f) + pow(y, 2.0f)) / (2.0f * pow(sigma, 2));
    return (1.0f / (2.0f * M_PI_H * pow(sigma, 2))) * exp(gaussianExponent);
}

float rand(int x, int y, int z) {
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

float2 randomGradient(float2 p, float iTime) {
    p = p + 0.01;
    float x = dot(p, float2(123.4, 234.5));
    float y = dot(p, float2(234.4, 367.5));
    float2 gradient = float2(x, y);
    gradient = sin(gradient);
    gradient = gradient * 56778.5312 * rand(x, y, x*y);
    
    gradient = sin(gradient + iTime);
    return gradient;
}

float perlinNoise(float2 uv, float iTime) {
    
    float2 gridID = floor(uv);
    float2 gridUV = fract(uv);
    
    float2 bl = gridID + float2(0.0, 0.0);
    float2 br = gridID + float2(1.0, 0.0);
    float2 tl = gridID + float2(0.0, 1.0);
    float2 tr = gridID + float2(1.0, 1.0);
    
    float2 gradBl = randomGradient(bl, iTime);
    float2 gradBr = randomGradient(br, iTime);
    float2 gradTl = randomGradient(tl, iTime);
    float2 gradTr = randomGradient(tr, iTime);
    
    float2 distFromPixelToBl = gridUV - float2(0.0, 0.0);
    float2 distFromPixelToBr = gridUV - float2(1.0, 0.0);
    float2 distFromPixelToTl = gridUV - float2(0.0, 1.0);
    float2 distFromPixelToTr = gridUV - float2(1.0, 1.0);
    
    float dotBl = dot(gradBl, distFromPixelToBl);
    float dotBr = dot(gradBr, distFromPixelToBr);
    float dotTl = dot(gradTl, distFromPixelToTl);
    float dotTr = dot(gradTr, distFromPixelToTr);
    
    gridUV = smoothstep(0.0, 1.0, gridUV);
    
    float b = mix(dotBl, dotBr, gridUV.x);
    float t = mix(dotTl, dotTr, gridUV.x);
    
    float perlin = abs(mix(b, t, gridUV.y));
    perlin = smoothstep(0.0, 0.32, perlin);
    
    return perlin;
}


kernel void cameraKernel(texture2d<float, access::read> lumaTexture [[ texture(0) ]],
                         texture2d<float, access::read> chromaTexture [[ texture(1) ]],
                         texture2d<float, access::write> presentTexture [[ texture(2) ]],
                         texture2d<float, access::write> outLuma [[ texture(3) ]],
                         texture2d<float, access::write> outChroma [[ texture(4) ]],
                         constant uint& lutSize [[ buffer(0) ]],
                         device float4* lutData [[ buffer(1) ]],
                         constant float *inputNoise [[ buffer(2) ]],
                         constant float *inputTime [[ buffer(3) ]],
                         uint2 gid [[ thread_position_in_grid ]]) {

    const float3x3 yCbCrToRGBMatrix = float3x3(1.0, 1.0, 1.0, 0.0, -0.343, 1.765, 1.4, -0.711, 0.0);
    const float3x3 rgbToYCbCrMatrix = float3x3(0.299, -0.169, 0.5, +0.587, -0.331, -0.419, 0.114, 0.5, -0.081);
    
    float3 yuv;
    yuv.x = lumaTexture.read(gid).r;
    yuv.yz = chromaTexture.read(uint2(gid.x/2, gid.y/2)).rg - float2(0.5, 0.5);
     
    if (float(*inputNoise) > 0.5) {
        float2 uv = float2(gid)/3.0f;
        yuv.x += (perlinNoise(uv, float(*inputTime) * 8.0f) - 0.5f)/5.0f;
    }

    float3 rgb = min(yCbCrToRGBMatrix * yuv, float3(1.0));
     
    if (lutSize > 2) {
       
        const float3 color = float3(rgb) * float(lutSize - 1);
        
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
        
        // Interpolating along the red axis
        const float3 c00 = mix(c000, c100, fract(color.r)); // Min Green index & Min Blue index
        const float3 c01 = mix(c001, c101, fract(color.r)); // Min Green index & Max Blue index
        
        const float3 c10 = mix(c010, c110, fract(color.r)); // Max Green index & Min Blue index
        const float3 c11 = mix(c011, c111, fract(color.r)); // Min Green index & Max Blue index

        // Interpolating along the green axis
        const float3 c0 = mix(c00, c10, fract(color.g)); // Min Blue index
        const float3 c1 = mix(c01, c11, fract(color.g)); // Max Blue index
        
        // Interpolating along the blue axis
        const float3 c = mix(c0, c1, fract(color.b));
        
        rgb = c;
    }
     
    float3 result = rgbToYCbCrMatrix * rgb;
    result.yz += float2(0.5, 0.5);
     
    presentTexture.write(float4(rgb, 1.0), gid);
    outLuma.write(result.x, gid);
    outChroma.write(float4(result.y, result.z, 1.0, 1.0), uint2(gid.x/2, gid.y/2));

}
