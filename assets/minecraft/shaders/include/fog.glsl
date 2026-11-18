#ifndef MINECRAFT_FOG_GLSL
#define MINECRAFT_FOG_GLSL

layout(std140) uniform Fog {
    vec4 FogColor;
    float FogEnvironmentalStart;
    float FogEnvironmentalEnd;
    float FogRenderDistanceStart;
    float FogRenderDistanceEnd;
    float FogSkyEnd;
    float FogCloudsEnd;
};

float linear_fog_value(float vertexDistance, float fogStart, float fogEnd) {
    if (vertexDistance <= fogStart) {
        return 0.0;
    } else if (vertexDistance >= fogEnd) {
        return 1.0;
    }

    return (vertexDistance - fogStart) / (fogEnd - fogStart);
}

// Soft exponential atmospheric fog ramp:
// Begins early (~40% of fogEnd) as a whisper-thin, highly transparent veil
// (~3% at 50% distance, ~7% at 60%, ~15% at 70%, ~30% at 80%) and ramps up
// exponentially to 100% at fogEnd to seamlessly round out the world horizon.
float atmospheric_fog_value(float dist, float fogStart, float fogEnd) {
    if (fogEnd <= 16.0 || fogStart < 0.0) {
        // Preserve short-range gameplay fogs (lava, powder snow, blindness/darkness)
        return linear_fog_value(dist, fogStart, fogEnd);
    }

    float stretchedStart = min(fogStart, fogEnd * 0.38);
    float t = clamp((dist - stretchedStart) / max(1.0, fogEnd - stretchedStart), 0.0, 1.0);

    // Normalized exponential ramp: (e^(k*t) - 1) / (e^k - 1) with C1 smooth onset
    const float k = 3.35;
    const float invDenom = 1.0 / (28.502733 - 1.0); // 1.0 / (exp(3.35) - 1.0)
    float expRamp = (exp(k * t) - 1.0) * invDenom;
    float smoothOnset = smoothstep(0.0, 0.12, t);
    return clamp(expRamp * smoothOnset, 0.0, 1.0);
}

float total_fog_value(float sphericalVertexDistance, float cylindricalVertexDistance, float environmentalStart, float environmantalEnd, float renderDistanceStart, float renderDistanceEnd) {
    // Use spherical 3D distance so the fog dome is completely round vertically and horizontally
    float roundDist = sphericalVertexDistance;
    float envFog = atmospheric_fog_value(roundDist, environmentalStart, environmantalEnd);
    float renFog = atmospheric_fog_value(roundDist, renderDistanceStart, renderDistanceEnd);
    return max(envFog, renFog);
}

vec4 apply_fog(vec4 inColor, float sphericalVertexDistance, float cylindricalVertexDistance, float environmentalStart, float environmantalEnd, float renderDistanceStart, float renderDistanceEnd, vec4 fogColor) {
    float fogValue = total_fog_value(sphericalVertexDistance, cylindricalVertexDistance, environmentalStart, environmantalEnd, renderDistanceStart, renderDistanceEnd);
    return vec4(mix(inColor.rgb, fogColor.rgb, fogValue * fogColor.a), inColor.a);
}

float fog_spherical_distance(vec3 pos) {
    return length(pos);
}

float fog_cylindrical_distance(vec3 pos) {
    // Round out cylindrical distance into a smooth 3D sphere
    return length(pos);
}

#endif
