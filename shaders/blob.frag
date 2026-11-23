#version 440
// The voice card's "thinking" blob: six metaballs merged with a smooth minimum
// (the same goo as the island). `merge` 0 lays them out in a line where the
// waveform was; 1 pulls them into one wobbling blob in the middle. `energy`
// speeds the wobble up (thinking) and `pop` swells it as it hands over.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float time;
    float merge;
    float energy;
    float pop;
    vec4 fill;
    vec4 glow;
};

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 c = size * 0.5;
    float span = size.x * 0.32;
    float d = 1e5;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        // spread: a row across the middle (where the bars were)
        vec2 line = c + vec2((fi / 5.0 - 0.5) * 2.0 * span, 0.0);
        // merged: orbiting the centre at different speeds and radii
        float sp = 0.9 + 0.35 * fi + energy * 0.8;
        float a = time * sp + fi * 1.047;
        float orbit = (6.0 + 4.0 * sin(time * 1.3 + fi * 2.1)) * (1.0 - pop * 0.6);
        vec2 ball = c + vec2(cos(a), sin(a * 1.17)) * orbit;
        vec2 pos = mix(line, ball, merge);
        float r = mix(4.0, 9.0 + 2.5 * sin(time * 2.0 + fi), merge) * (1.0 + pop * 1.6);
        d = smin(d, length(p - pos) - r, mix(4.0, 16.0, merge));
    }
    float a = clamp(0.5 - d, 0.0, 1.0);
    // a soft halo that breathes with the wobble
    float halo = glow.a * (1.0 - smoothstep(0.0, 22.0, d)) * (1.0 - a) * merge;
    vec4 col = fill * a + vec4(glow.rgb, 1.0) * halo;
    fragColor = col * qt_Opacity;
}
