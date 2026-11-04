#include <metal_stdlib>
using namespace metal;

/**
 * Kernel 1: batchCheckInliersCubic
 *
 * Processes each combination of a model and a point to determine if the point
 * is an inlier under a cubic polynomial (A*x^3 + B*x^2 + C*x + D).
 *
 * Parameters:
 *  - pointsBuffer:  float2 array holding (x,y) coordinates for lane points.
 *  - modelsBuffer:  float4 array holding (A,B,C,D) for each randomly generated model.
 *  - inliersBuffer: int array of size (numModels * numPoints), storing inlier flags.
 *  - numPoints:     total number of lane points.
 *  - numModels:     total number of models.
 *  - threshold:     distance threshold for inlier classification.
 *
 * Each thread (id) maps to one (modelIdx, pointIdx) pair in row-major form.
 * Writes 1 if the point is within 'threshold' distance, else 0.
 */
kernel void batchCheckInliersCubic(
    const device float2* pointsBuffer  [[ buffer(0) ]],
    const device float4* modelsBuffer [[ buffer(1) ]],
    device int* inliersBuffer         [[ buffer(2) ]],
    constant uint& numPoints          [[ buffer(3) ]],
    constant uint& numModels          [[ buffer(4) ]],
    constant float& threshold         [[ buffer(5) ]],
    uint id                           [[ thread_position_in_grid ]]
)
{
    // total = numModels * numPoints
    uint total = numModels * numPoints;
    if (id >= total) return;

    uint modelIdx = id / numPoints;
    uint pointIdx = id % numPoints;

    float2 p = pointsBuffer[pointIdx];
    float x = p.x;
    float y = p.y;

    float4 m = modelsBuffer[modelIdx]; // (A,B,C,D)
    float A = m.x;
    float B = m.y;
    float C = m.z;
    float D = m.w;

    // Evaluate yPred = A*x^3 + B*x^2 + C*x + D
    float x2 = x * x;
    float x3 = x2 * x;
    float yPred = A * x3 + B * x2 + C * x + D;
    float dist = fabs(y - yPred);

    inliersBuffer[id] = (dist < threshold) ? 1 : 0;
}

/**
 * Kernel 2: sumInliersCubic
 *
 * Sums inlier counts for each model across all lane points. Each thread corresponds
 * to one model index. The function sums the values from i*numPoints to i*numPoints + numPoints - 1.
 *
 * Parameters:
 *  - inliersBuffer: array of size (numModels * numPoints) storing 1 or 0 for each (model, point).
 *  - modelCounts:   output array of size numModels for total inliers per model.
 *  - numPoints:     total number of lane points.
 *  - numModels:     total number of models.
 */
kernel void sumInliersCubic(
    const device int* inliersBuffer  [[ buffer(0) ]],
    device int* modelCounts          [[ buffer(1) ]],
    constant uint& numPoints         [[ buffer(2) ]],
    constant uint& numModels         [[ buffer(3) ]],
    uint id                          [[ thread_position_in_grid ]]
)
{
    if (id >= numModels) return;

    int count = 0;
    uint offset = id * numPoints;
    for (uint p = 0; p < numPoints; p++) {
        count += inliersBuffer[offset + p];
    }
    modelCounts[id] = count;
}
