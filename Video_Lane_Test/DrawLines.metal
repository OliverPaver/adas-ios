#include <metal_stdlib>
using namespace metal;

/**
 * Shared struct for line drawing.
 */
struct LinePoint {
    ushort x;
    ushort y;
    float4 color;
};

/**
 * Kernel: clearOverlayTexture
 *
 * Clears the output texture to transparent by writing float4(0,0,0,0) to each pixel.
 * The thread grid covers the entire texture; out-of-bounds threads are discarded.
 */
kernel void clearOverlayTexture(
    texture2d<float, access::write> outTexture [[ texture(0) ]],
    uint2 tid                                [[ thread_position_in_threadgroup ]],
    uint2 gid                                [[ threadgroup_position_in_grid ]],
    uint2 groupSize                          [[ threads_per_threadgroup ]],
    uint2 gridSize                           [[ threadgroups_per_grid ]]
)
{
    uint2 globalID;
    globalID.x = gid.x * groupSize.x + tid.x;
    globalID.y = gid.y * groupSize.y + tid.y;

    if (globalID.x >= outTexture.get_width() ||
        globalID.y >= outTexture.get_height()) {
        return;
    }

    float4 clr = float4(0.0, 0.0, 0.0, 0.0);
    outTexture.write(clr, globalID);
}

/**
 * Kernel: drawPointsKernel
 *
 * Draws colored points into the texture at locations specified by linePoints.
 * Each thread processes exactly one LinePoint entry.
 *
 * Parameters:
 *  - outTexture:   writable texture for drawing.
 *  - linePoints:   array of (x, y, color).
 *  - lineCount:    number of valid points in the linePoints array.
 */
kernel void drawPointsKernel(
    texture2d<float, access::write> outTexture [[ texture(0) ]],
    device LinePoint* linePoints               [[ buffer(0) ]],
    constant uint& lineCount                   [[ buffer(1) ]],
    uint id                                    [[ thread_position_in_grid ]]
)
{
    if (id >= lineCount) return;

    LinePoint p = linePoints[id];
    uint x = p.x;
    uint y = p.y;

    if (x < outTexture.get_width() && y < outTexture.get_height()) {
        outTexture.write(p.color, uint2(x, y));
    }
}
