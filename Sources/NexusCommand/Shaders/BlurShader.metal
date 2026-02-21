#include <metal_stdlib>
using namespace metal;

// Gaussian blur shader for command bar background
// Applied via SwiftUI .layerEffect modifier
[[ stitchable ]] half4 gaussianBlur(
    float2 position,
    SwiftUI::Layer layer,
    float radius
) {
    half4 color = half4(0.0);
    float totalWeight = 0.0;
    int samples = int(radius);

    for (int x = -samples; x <= samples; x++) {
        for (int y = -samples; y <= samples; y++) {
            float2 offset = float2(float(x), float(y));
            float distance = length(offset);
            float weight = exp(-(distance * distance) / (2.0 * radius * radius));

            color += layer.sample(position + offset) * weight;
            totalWeight += weight;
        }
    }

    return color / totalWeight;
}
