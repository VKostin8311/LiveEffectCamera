//
//  pixellate.metal
//  Lumagine
//
//  Created by Владимир Костин on 08.12.2023.
//

#include <metal_stdlib>
using namespace metal;



kernel void pixellateKernel(texture2d<half, access::read_write> lumaTexture [[ texture(0) ]],
                            texture2d<half, access::read_write> chromaTexture [[ texture(1) ]],
                            texture2d<half, access::write> presentTexture [[ texture(2) ]],
                            constant uint& lutSize [[ buffer(0) ]],
                            device float4* lutData [[ buffer(1) ]],
                            constant float& intensity [[ buffer(2) ]],
                            uint2 gid [[ thread_position_in_grid ]]
                            ) {

    const half3x3 yCbCrToRGBMatrix = half3x3(1.0, 1.0, 1.0, 0.0, -0.343, 1.765, 1.4, -0.711, 0.0);
    const half3x3 rgbToYCbCrMatrix = half3x3(0.299, -0.169, 0.5, +0.587, -0.331, -0.419, 0.114, 0.5, -0.081);
    
    half3 yuv;
    yuv.x = lumaTexture.read(gid).r;
    yuv.yz = chromaTexture.read(uint2(gid.x/2, gid.y/2)).rg - half2(0.5, 0.5);
    
    half3 rgb = clamp(yCbCrToRGBMatrix * yuv, half3(0.0), half3(1.0));
    
    if (lutSize > 2) {
       
        half3 luttedColor = 0.0;
        
        const half3 color = rgb * half(lutSize - 1);
        
        const uint minBlueIndex = floor(color.b) * lutSize * lutSize; // Calculate min blue index
        const uint maxBlueIndex = ceil(color.b) * lutSize * lutSize;  // Calculate max blue index
        
        const uint minGreenIndex = floor(color.g) * lutSize; // Calculate min green index
        const uint maxGreenIndex = ceil(color.g) * lutSize; // Calculate max green index
        
        const uint minRedIndex = floor(color.r); // Calculate min red index
        const uint maxRedIndex = ceil(color.r); // Calculate max red index
        
        // Fetch & interpolate blue colors
        luttedColor.b = mix(half(lutData[minBlueIndex].b), half(lutData[maxBlueIndex].b), fract(color.b));
         
        // Fetch & interpolate green colors from min blue rows
        const half minGreen = mix(half(lutData[minBlueIndex + minGreenIndex].g), half(lutData[minBlueIndex + maxGreenIndex].g), fract(color.g));
        // Fetch & interpolate green colors from max blue rows
        const half maxGreen = mix(half(lutData[maxBlueIndex + minGreenIndex].g), half(lutData[maxBlueIndex + maxGreenIndex].g), fract(color.g));
        
        luttedColor.g = mix(minGreen, maxGreen, fract(color.b)); // Interpolate result green colors
        
        // Fetch & interpolate red color from min blue & min green indices
        const half minMinRed = mix(half(lutData[minBlueIndex + minGreenIndex + minRedIndex].r), half(lutData[minBlueIndex + minGreenIndex + maxRedIndex].r), fract(color.r));
        // Fetch & interpolate red color from min blue & max green indices
        const half minMaxRed = mix(half(lutData[minBlueIndex + maxGreenIndex + minRedIndex].r), half(lutData[minBlueIndex + maxGreenIndex + maxRedIndex].r), fract(color.r));
        
        // Fetch & interpolate red color from max blue & min green indices
        const half maxMinRed = mix(half(lutData[maxBlueIndex + minGreenIndex + minRedIndex].r), half(lutData[maxBlueIndex + minGreenIndex + maxRedIndex].r), fract(color.r));
        // Fetch & interpolate red color from max blue & max green indices
        const half maxMaxRed = mix(half(lutData[maxBlueIndex + maxGreenIndex + minRedIndex].r), half(lutData[maxBlueIndex + maxGreenIndex + maxRedIndex].r), fract(color.r));
        
        const half minRed = mix(minMinRed, minMaxRed, fract(color.g)); // Interpolate red colors from min blue indices
        const half maxRed = mix(maxMinRed, maxMaxRed, fract(color.g)); // Interpolate red colors from max blue indices
        luttedColor.r = mix(minRed, maxRed, fract(color.b)); // Interpolate result red colors
        
        rgb = mix(rgb, luttedColor, intensity);
    }
     
    half3 result = rgbToYCbCrMatrix * rgb;
    result.yz += half2(0.5, 0.5);

    lumaTexture.write(result.x, gid);
    chromaTexture.write(half4(result.y, result.z, 1.0, 1.0), uint2(gid.x/2, gid.y/2));
    presentTexture.write(half4(rgb, 1.0), gid);
}


