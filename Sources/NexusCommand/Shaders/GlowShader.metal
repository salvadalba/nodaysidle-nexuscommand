#include <metal_stdlib>
using namespace metal;

// Glow/bloom effect shader for focused elements
// Applied via SwiftUI .layerEffect modifier
[[ stitchable ]] half4 glowEffect(
    float2 position,
    SwiftUI::Layer layer,
    float red,
    float green,
    float blue,
    float intensity
) {
    half4 original = layer.sample(position);
    half4 glowColor = half4(half(red), half(green), half(blue), 1.0h);

    // Sample surrounding pixels for bloom
    half4 bloom = half4(0.0);
    float blurRadius = 4.0;
    int samples = 4;
    float totalWeight = 0.0;

    for (int x = -samples; x <= samples; x++) {
        for (int y = -samples; y <= samples; y++) {
            float2 offset = float2(float(x), float(y)) * blurRadius;
            float weight = 1.0 / (1.0 + length(offset));
            bloom += layer.sample(position + offset) * weight;
            totalWeight += weight;
        }
    }
    bloom /= totalWeight;

    // Combine: original + glow color tinted bloom
    half4 tintedBloom = bloom * glowColor * half(intensity);
    half4 result = original + tintedBloom * (1.0h - original.a * 0.5h);
    result.a = original.a;

    return result;
}
