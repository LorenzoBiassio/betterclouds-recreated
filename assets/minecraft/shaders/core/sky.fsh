#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>

layout(location = 0) in vec3 vSkyPos;
layout(location = 1) in float vIsTopSky;

layout(location = 0) out vec4 fragColor;

void main() {
    vec3 rayDir = normalize(vSkyPos);
    float viewY = rayDir.y;

    if (vIsTopSky > 0.5) {
        // Subtle atmospheric Rayleigh gradient from lower sky (viewY ~ 0.03..0.25) to overhead zenith (viewY -> 1.0):
        // Slightly brighter, airy azure near the cloud band transitioning to a deeper cobalt/sapphire zenith overhead.
        float zenithFactor = pow(clamp((viewY - 0.10) / 0.90, 0.0, 1.0), 1.35);
        float lowerSkyGlow = smoothstep(0.32, 0.025, viewY) * smoothstep(-0.04, 0.025, viewY);

        vec3 baseSky   = ColorModulator.rgb;
        vec3 zenithSky = baseSky * vec3(0.86, 0.90, 0.98);
        vec3 lowerSky  = mix(baseSky * 1.04, FogColor.rgb, 0.10);

        vec3 skyGrad = mix(baseSky, zenithSky, zenithFactor);
        skyGrad = mix(skyGrad, lowerSky, lowerSkyGlow * 0.65);

        // Distant clouds sit around viewY = +0.04 to +0.14.
        // Keep blue sky all the way down to viewY = +0.025 (below the cloud lines!),
        // then smoothly blend into FogColor right at the low terrain horizon (-0.055 .. +0.025).
        float t = clamp((0.025 - viewY) / (0.025 - (-0.055)), 0.0, 1.0);
        float horizonFog = (exp(2.8 * t) - 1.0) / (exp(2.8) - 1.0);
        horizonFog *= smoothstep(0.0, 0.15, t);
        fragColor = vec4(mix(skyGrad, FogColor.rgb, horizonFog * FogColor.a), ColorModulator.a);
    } else {
        // Bottom void disc blends into FogColor near the lowered horizon
        float t = clamp((viewY - (-0.18)) / ((-0.055) - (-0.18)), 0.0, 1.0);
        float horizonFog = t * t * (3.0 - 2.0 * t);
        fragColor = vec4(mix(ColorModulator.rgb, FogColor.rgb, horizonFog * FogColor.a), ColorModulator.a);
    }
}
