#version 440
// The Weather tab's backdrop: light motion matched to the weather, drawn
// faintly behind the card's text and clipped to its rounded corners.
// kind (modules/dashboard/sky.js): 1 sun, 2 stars, 3 cloud/fog, 4 rain,
// 5 snow, 6 storm. amount 0..1 is how much of it; tint colours the sun and
// stars; time is in seconds.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float time;
    float kind;
    float amount;
    float radius;
    vec4 tint;
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
    return v;
}

float roundBox(vec2 p, vec2 h, float r) {
    vec2 q = abs(p) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// slanted streaks falling through cells; `layer` varies size and speed
float rain(vec2 p, float layer) {
    float scale = 26.0 + layer * 14.0;
    vec2 q = p / scale;
    q.x += q.y * 0.18;                       // a little wind
    q.y -= time * (2.4 + layer * 0.9);
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float h = hash(cell + layer * 17.0);
    if (h > amount * 0.9 + 0.08) return 0.0;  // fewer drops when it's light
    float x = abs(f.x - (0.2 + 0.6 * hash(cell + 3.1)));
    float len = 0.35 + 0.3 * h;
    float y = fract(f.y + h);
    return (1.0 - smoothstep(0.0, 0.035, x)) * smoothstep(0.0, len, y) * step(y, len + 0.02) * (0.5 + 0.5 * layer);
}

float snow(vec2 p, float layer) {
    float scale = 34.0 + layer * 20.0;
    vec2 q = p / scale;
    q.y -= time * (0.25 + layer * 0.12);
    q.x += sin(q.y * 2.0 + layer * 3.0 + time * 0.6) * 0.15;
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float h = hash(cell + layer * 9.0);
    if (h > amount * 0.85 + 0.1) return 0.0;
    vec2 c = vec2(0.25 + 0.5 * hash(cell + 1.7), 0.25 + 0.5 * hash(cell + 5.3));
    float r = (1.5 + 1.0 * layer) / scale;  // 1.5–3.5 px, in cell units
    return 1.0 - smoothstep(r * 0.6, r, length(f - c));
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float inside = clamp(0.5 - roundBox(p - size * 0.5, size * 0.5, radius), 0.0, 1.0);
    vec3 white = vec3(1.0);
    vec4 col = vec4(0.0);
    int k = int(kind + 0.5);

    if (k == 1) {            // sun: a warm glow up in the corner that breathes, slow rays
        vec2 c = vec2(size.x * 0.82, size.y * 0.05);
        vec2 d = p - c;
        float r = length(d) / size.y;
        float rays = 0.5 + 0.5 * sin(atan(d.y, d.x) * 9.0 + time * 0.25);
        float g = exp(-r * 2.6) * (0.75 + 0.25 * sin(time * 0.7)) + rays * exp(-r * 3.5) * 0.35;
        col = vec4(tint.rgb, 1.0) * g * 0.22;
    } else if (k == 2) {     // stars: a few that twinkle
        vec2 q = p / 18.0;
        vec2 cell = floor(q);
        float h = hash(cell);
        if (h > 0.86) {
            vec2 c = vec2(hash(cell + 2.3), hash(cell + 7.1));
            float d = length(fract(q) - c);
            float tw = 0.5 + 0.5 * sin(time * (1.0 + 2.0 * h) + h * 40.0);
            col = vec4(mix(white, tint.rgb, 0.4), 1.0) * (1.0 - smoothstep(0.0, 0.07, d)) * tw * 0.5;
        }
    } else if (k == 3) {     // cloud and fog: soft banks drifting by
        vec2 q = p / size.y * 2.2 + vec2(time * 0.04, 0.0);
        float n = fbm(q) * 0.7 + fbm(q * 0.5 - vec2(time * 0.02, 0.0)) * 0.5;
        float v = smoothstep(0.55 - amount * 0.25, 1.0, n);
        col = vec4(white, 1.0) * v * (0.06 + 0.1 * amount);
    } else if (k == 4 || k == 6) { // rain (and storm)
        float s = rain(p, 0.0) * 0.6 + rain(p, 1.0) + rain(p, 2.0) * 0.8;
        col = vec4(white, 1.0) * s * (0.08 + 0.12 * amount);
        if (k == 6) {        // now and then a flash
            float t = time * 0.35;
            float f = hash(vec2(floor(t), 4.2));
            float flash = f > 0.7 ? exp(-fract(t) * 14.0) * (0.5 + 0.5 * sin(fract(t) * 90.0)) : 0.0;
            col += vec4(white, 1.0) * max(flash, 0.0) * 0.12;
        }
    } else if (k == 5) {     // snow: flakes that sway as they fall
        float s = snow(p, 0.0) * 0.5 + snow(p, 1.0) * 0.8 + snow(p, 2.0);
        col = vec4(white, 1.0) * s * 0.4;
    }

    fragColor = col * inside * qt_Opacity;
}
