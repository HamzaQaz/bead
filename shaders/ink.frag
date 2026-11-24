#version 440
// Colours an item's ink (its alpha) with a gradient across it, `from` on
// the left to `to` on the right. `shine` sweeps a slanted band of light
// across it (0 → 1, left to right; it's off the ink at both ends).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 from;
    vec4 to;
    float shine;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float a = texture(source, qt_TexCoord0).a;
    vec3 c = mix(from.rgb, to.rgb, smoothstep(0.1, 0.9, qt_TexCoord0.x));
    float band = (qt_TexCoord0.x + (qt_TexCoord0.y - 0.5) * 0.12 - mix(-0.25, 1.25, shine)) / 0.09;
    c = mix(c, vec3(1.0), 0.85 * exp(-band * band));
    fragColor = vec4(c * a, a) * qt_Opacity;
}
