#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:oit.glsl>

layout(location = 0) in float vertexDistance;
layout(location = 1) in vec4 vertexColor;
layout(location = 2) in float vLocalY;
layout(location = 3) in float vClusterDensity;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

vec4 calculateFinalColor(vec4 color) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    #endif
    return color;
}

void main() {
    float verticalGrad = smoothstep(0.0, 1.0, vLocalY);

    // Base daytime vertical gradient across each 3D cube face
    vec3 bottomShade = vertexColor.rgb * vec3(0.92, 0.95, 1.00);
    vec3 topShade    = min(vec3(1.0), vertexColor.rgb * 1.04);
    vec3 shadedRgb   = mix(bottomShade, topShade, verticalGrad);

    // --- Atmospheric Time-of-Day Tinting (Sunset / Sunrise & Moonlit Night) ---
    // Detect luminance & horizon warmth so midday (cloudLuma > 0.86, fogWarmth == 0) is 100% untouched
    float cloudLuma = dot(vertexColor.rgb, vec3(0.299, 0.587, 0.114));
    float fogWarmth = clamp((FogColor.r - FogColor.b) * 2.2, 0.0, 1.0);
    float twilightLuma = smoothstep(0.18, 0.42, cloudLuma) * (1.0 - smoothstep(0.72, 0.88, cloudLuma));
    float goldenHour = clamp(max(fogWarmth, twilightLuma * 0.75), 0.0, 1.0);

    if (goldenHour > 0.001) {
        // Low sun illuminates cloud undersides & fringes with warm peach/amber while tops catch rose-violet sky bounce
        vec3 warmUnderGlow = mix(vec3(1.00, 0.64, 0.44), max(FogColor.rgb * 1.25, vec3(0.98, 0.58, 0.40)), 0.55) * cloudLuma * 1.35;
        vec3 twilightTop   = vertexColor.rgb * vec3(0.96, 0.88, 1.04);
        float underMask    = (1.0 - verticalGrad * 0.75) * mix(1.0, 0.72, vClusterDensity);
        vec3 sunsetRgb     = mix(twilightTop, warmUnderGlow, underMask);
        shadedRgb          = mix(shadedRgb, sunsetRgb, goldenHour * 0.65);
    }

    // Moonlit night contrast: subtle silvery-blue top highlight so 3D cube layers stay visible at night
    float nightFactor = 1.0 - smoothstep(0.14, 0.34, cloudLuma);
    if (nightFactor > 0.001) {
        vec3 moonlightTop  = vertexColor.rgb * vec3(1.10, 1.18, 1.38) + vec3(0.015, 0.022, 0.038);
        vec3 nightShadow   = vertexColor.rgb * vec3(0.82, 0.88, 1.02);
        vec3 nightRgb      = mix(nightShadow, moonlightTop, verticalGrad);
        shadedRgb          = mix(shadedRgb, nightRgb, nightFactor * 0.80);
    }

    // Smooth camera proximity mist fade (12 to 28 blocks) when flying through a cloud puff
    // so near faces dissolve softly before reaching the camera or compressing OIT depth bounds
    float cameraFade = smoothstep(12.0, 28.0, vertexDistance);

    // Per-cube opacity: keeps distant clouds (>360 blocks) at 0.18..0.25 while boosting
    // closer/overhead clouds up to 0.31..0.44 to compensate for steeper upward viewing angles
    float nearAlphaBoost = 1.0 - smoothstep(65.0, 360.0, vertexDistance);
    #ifdef OIT
    float farAlpha  = mix(0.18, 0.25, vClusterDensity);
    float nearAlpha = mix(0.31, 0.44, vClusterDensity);
    float puffAlpha = mix(farAlpha, nearAlpha, nearAlphaBoost);
    #else
    float farAlpha  = mix(0.24, 0.34, vClusterDensity);
    float nearAlpha = mix(0.38, 0.52, vClusterDensity);
    float puffAlpha = mix(farAlpha, nearAlpha, nearAlphaBoost);
    #endif

    vec4 color = vec4(shadedRgb, vertexColor.a * puffAlpha * cameraFade);
    #ifndef OIT_DEPTH_BOUNDS
    // Soft exponential distance alpha fade into the blue sky
    float cloudFog = atmospheric_fog_value(vertexDistance, FogCloudsEnd * 0.45, FogCloudsEnd);
    color.a *= 1.0 - cloudFog;
    #endif

    if (color.a < 0.01) {
        discard;
    }

    #ifdef OIT_DEPTH_BOUNDS
    // Clamp hardware depth write to the far horizon bound so even very close cloud faces
    // when flying inside a cloud never depth-cull other clouds behind them
    gl_FragDepth = min(gl_FragCoord.z, 0.00001);
    #endif

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}
