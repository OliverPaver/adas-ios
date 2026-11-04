#include <metal_stdlib>
using namespace metal;

/**
 * Kernel 1: markCorePoints
 *
 * Classifies each point as core or noise by counting how many points lie
 * within epsilonSquared distance in embedding space. If count >= minPoints,
 * the point is marked as core (1); otherwise, it remains noise (0).
 *
 * Parameters:
 *  - embeddings:     float4 array (e.g., lane embedding features).
 *  - coreFlags:      integer array where 1 indicates a core point and 0 indicates noise.
 *  - numPoints:      total number of points.
 *  - epsilonSquared: squared search distance for neighborhood checks.
 *  - minPoints:      minimum required neighbors to qualify as core.
 */
kernel void markCorePoints(
    const device float4* embeddings     [[ buffer(0) ]],
    device int* coreFlags               [[ buffer(1) ]],
    constant uint& numPoints            [[ buffer(2) ]],
    constant float& epsilonSquared      [[ buffer(3) ]],
    constant uint& minPoints            [[ buffer(4) ]],
    uint id                             [[ thread_position_in_grid ]]
)
{
    if (id >= numPoints) return;

    float4 point = embeddings[id];
    uint count = 0;
    for (uint j = 0; j < numPoints; j++) {
        float4 diff = point - embeddings[j];
        float d2 = dot(diff, diff);
        if (d2 < epsilonSquared) {
            count++;
        }
    }
    coreFlags[id] = (count >= minPoints) ? 1 : 0;
}

/**
 * Kernel 2: initializeLabels
 *
 * Assigns initial labels based on core flags. Each core point is labeled
 * with its own ID; noise points remain labeled -1.
 *
 * Parameters:
 *  - labels:    output labels array (size = numPoints).
 *  - numPoints: total number of points.
 *  - coreFlags: array indicating core (1) or noise (0) for each point.
 */
kernel void initializeLabels(
    device int* labels            [[ buffer(0) ]],
    constant uint& numPoints      [[ buffer(1) ]],
    const device int* coreFlags   [[ buffer(2) ]],
    uint id                       [[ thread_position_in_grid ]]
)
{
    if (id >= numPoints) return;
    labels[id] = (coreFlags[id] == 1) ? int(id) : -1;
}

/**
 * Kernel 3: propagateLabels
 *
 * Propagates labels by examining neighbors within epsilonSquared. If a neighbor
 * has a valid label smaller than the current label, the current label is updated.
 *
 * Parameters:
 *  - embeddings:     float4 array of points in embedding space.
 *  - labels:         array of current labels.
 *  - numPoints:      total number of points.
 *  - epsilonSquared: squared radius for neighbors.
 */
kernel void propagateLabels(
    const device float4* embeddings [[ buffer(0) ]],
    device int* labels              [[ buffer(1) ]],
    constant uint& numPoints        [[ buffer(2) ]],
    constant float& epsilonSquared  [[ buffer(3) ]],
    uint id                         [[ thread_position_in_grid ]]
)
{
    if (id >= numPoints) return;

    int currentLabel = labels[id];
    if (currentLabel == -1) return; // skip noise

    float4 point = embeddings[id];
    for (uint j = 0; j < numPoints; j++) {
        if (j == id) continue;
        float4 diff = point - embeddings[j];
        float d2 = dot(diff, diff);
        if (d2 < epsilonSquared) {
            int neighborLabel = labels[j];
            if (neighborLabel != -1 && neighborLabel < currentLabel) {
                currentLabel = neighborLabel;
            }
        }
    }
    labels[id] = currentLabel;
}
