#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;

layout(location = 0) out vec3 vSkyPos;
layout(location = 1) out float vIsTopSky;

void main() {
    vec3 pos = Position;
    float radialDist = length(Position.xz);

    if (Position.y > 0.0) {
        // Top blue sky dome: arch the zenith higher and pull the outer rim well below
        // the geometric horizon (y = -56 at r = 512, ~-6.2 deg) so blue sky is rendered
        // all the way underneath the distant cloud lines down to the terrain horizon.
        vIsTopSky = 1.0;
        if (radialDist < 1.0) {
            pos.y = 120.0;
        } else {
            pos.y = -56.0;
        }
    } else {
        // Bottom dark void disc: push further down so it never overlaps the lowered sky rim
        vIsTopSky = 0.0;
        if (radialDist < 1.0) {
            pos.y = -96.0;
        } else {
            pos.y = -72.0;
        }
    }

    gl_Position = ProjMat * ModelViewMat * vec4(pos, 1.0);
    vSkyPos = pos;
}
