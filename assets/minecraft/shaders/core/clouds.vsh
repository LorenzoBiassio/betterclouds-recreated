#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

const int FLAG_MASK_DIR = 7;
const int FLAG_INSIDE_FACE = 1 << 4;
const int FLAG_USE_TOP_COLOR = 1 << 5;
const int FLAG_EXTRA_Z = 1 << 6;
const int FLAG_EXTRA_X = 1 << 7;

layout(std140) uniform CloudInfo {
    vec4 CloudColor;
    vec3 CloudOffset;
    vec3 CellSize;
};

uniform isamplerBuffer CloudFaces;

layout(location = 0) out float vertexDistance;
layout(location = 1) out vec4 vertexColor;
layout(location = 2) out float vLocalY;
layout(location = 3) out float vClusterDensity;

const int packedX = 0xF03CC3;
const int packedY = 0x6666F0;
const int packedZ = 0xC3F066;

vec3 vertex(int index) {
    vec3 pos = vec3(0.0);
    pos.x = float((packedX >> index) & 1);
    pos.y = float((packedY >> index) & 1);
    pos.z = float((packedZ >> index) & 1);
    return pos;
}

// Crisp directional cube shading so overlapping translucent 3D cubes show distinct layered faces
const vec4[] faceColors = vec4[](
    // Bottom face (0: -Y)
    vec4(0.84, 0.89, 0.97, 1.0),
    // Top face (1: +Y)
    vec4(1.00, 1.00, 1.00, 1.0),
    // North face (2: -Z)
    vec4(0.90, 0.93, 0.99, 1.0),
    // South face (3: +Z)
    vec4(0.90, 0.93, 0.99, 1.0),
    // West face (4: -X)
    vec4(0.95, 0.97, 1.00, 1.0),
    // East face (5: +X)
    vec4(0.95, 0.97, 1.00, 1.0)
);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float fbm2(vec2 p) {
    float v = 0.0;
    v += 0.60 * valueNoise(p);
    v += 0.40 * valueNoise(p * 2.13 + vec2(19.7, 31.3));
    return v;
}

void main() {
    int quadId = gl_VertexIndex / 4;
    int quadVertex = gl_VertexIndex % 4;
    int index = quadId * 3;

    int rawX = texelFetch(CloudFaces, index).r;
    int rawZ = texelFetch(CloudFaces, index + 1).r;
    int dirAndFlags = texelFetch(CloudFaces, index + 2).r;
    int direction = dirAndFlags & FLAG_MASK_DIR;
    bool isInsideFace = (dirAndFlags & FLAG_INSIDE_FACE) == FLAG_INSIDE_FACE;
    bool useTopColor = (dirAndFlags & FLAG_USE_TOP_COLOR) == FLAG_USE_TOP_COLOR;
    int cellX = (rawX << 1) | ((dirAndFlags & FLAG_EXTRA_X) >> 7);
    int cellZ = (rawZ << 1) | ((dirAndFlags & FLAG_EXTRA_Z) >> 6);

    // Skip vanilla's duplicate inverted inside-shell faces (emitted only for |cellX|<=1, |cellZ|<=1)
    if (isInsideFace) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        vertexDistance = 0.0;
        vertexColor = vec4(0.0);
        vLocalY = 0.0;
        vClusterDensity = 0.0;
        return;
    }

    vec3 faceVertex = vertex((direction * 4) + quadVertex);

    // Continuous camera-relative horizontal coordinates of this cell (100% smooth across all axes and cell boundaries)
    vec2 baseMinXZ = (vec2(float(cellX), float(cellZ)) * CellSize.xz) + CloudOffset.xz;
    vec2 baseMaxXZ = baseMinXZ + CellSize.xz;
    vec2 cellCenterXZ = 0.5 * (baseMinXZ + baseMaxXZ);

    // Quadrant-independent continuous cluster density field so crossing X=0 or Z=0 never pops
    float clusterCore = smoothstep(0.22, 0.76, fbm2(cellCenterXZ * 0.018 + vec2(3.7, 8.2)));

    // Subtle organic XZ offset so puffs don't sit on a rigid grid, while keeping neighboring puffs tightly overlapping
    vec2 jitterXZ = vec2(
        valueNoise(cellCenterXZ * 0.045 + vec2(11.3, 27.1)) - 0.5,
        valueNoise(cellCenterXZ * 0.045 + vec2(53.7, 9.4)) - 0.5
    ) * 4.5;

    float sizeVariation = valueNoise(cellCenterXZ * 0.032 + vec2(7.1, 13.4));
    float cottonTurret  = valueNoise(cellCenterXZ * 0.052 + vec2(67.3, 29.8));
    float horizDist = length(cellCenterXZ);
    float nearFactor = 1.0 - smoothstep(60.0, 360.0, horizDist);

    // Altitude factor: smoothly boosts cotton-ball roundness when flying near or above the cloud deck
    float flyAltitudeFactor = 1.0 - smoothstep(10.0, 95.0, max(0.0, CloudOffset.y));

    // Compact horizontal expansion at distance (5.2 to 7.4 blocks), expanding slightly (+1.8 blocks) nearby
    float padXZ = mix(5.2, 7.4, 0.65 * clusterCore + 0.35 * sizeVariation) + 1.8 * nearFactor;

    vec2 newMinXZ = baseMinXZ + jitterXZ - vec2(padXZ);
    vec2 newMaxXZ = baseMaxXZ + jitterXZ + vec2(padXZ);

    // Multi-layered altitude waves
    float macroWave  = (fbm2(cellCenterXZ * 0.0055) - 0.5) * 24.0;
    float localStep  = (valueNoise(cellCenterXZ * 0.038 + vec2(41.2, 18.9)) - 0.5) * mix(7.5, 11.5, max(nearFactor, flyAltitudeFactor));
    float altitudeOffset = macroWave + localStep + (clusterCore - 0.35) * 3.5;

    // Cotton-ball 3D vertical profile:
    // - Underside (bottomDepth) stays gently terraced so the view from the ground remains clean.
    // - Upper dome (topHeight) billows tall and round in cluster centers with cumulus turret variation
    //   so clouds look like fluffy 3D cotton balls from the side and when flying!
    float volumeScale = mix(1.0, 1.55, max(nearFactor, flyAltitudeFactor * 0.85));
    float bottomDepth = (mix(2.5, 6.2, clusterCore) + sizeVariation * 1.8) * volumeScale;
    float topHeight   = (mix(5.5, 16.5, clusterCore * clusterCore) + cottonTurret * 6.5 + sizeVariation * 3.0) * volumeScale;

    float baseCenterY = CloudOffset.y + 0.5 * CellSize.y + altitudeOffset;
    float newMinY = baseCenterY - bottomDepth;
    float newMaxY = baseCenterY + topHeight;

    vec3 pos;
    if (useTopColor) {
        pos = (faceVertex * CellSize) + (vec3(float(cellX), 0.0, float(cellZ)) * CellSize) + CloudOffset;
    } else {
        pos.xz = mix(newMinXZ, newMaxXZ, faceVertex.xz);
        pos.y  = mix(newMinY, newMaxY, faceVertex.y);
    }

    gl_Position = ProjMat * ModelViewMat * vec4(pos, 1.0);

    vertexDistance = fog_spherical_distance(pos);
    vLocalY = faceVertex.y;
    vClusterDensity = clusterCore;
    vertexColor = (useTopColor ? faceColors[1] : faceColors[direction]) * CloudColor;
}
