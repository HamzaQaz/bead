#version 440
// The welcome card's backdrop: three of the theme's colours drifting as soft
// lights over the card's own colour. `flood` 1 lets them cover the card (the
// intro, while "bead." is written over it); 0 leaves a faint glow at the top.
// `phase` shifts where they sit (it moves with each step, so pages drift into
// one another). The card's rounded corners are cut here too (`radius`).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float time;
    float radius;
    float flood;
    float phase;
    vec4 base;
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

float roundRect(vec2 p, vec2 half_, float r) {
    vec2 q = abs(p) - half_ + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float light(vec2 uv, vec2 at, float spread) {
    vec2 d = uv - at;
    return exp(-dot(d, d) / spread);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 uv = qt_TexCoord0;
    float t = time;
    vec2 w = uv + 0.06 * vec2(sin(uv.y * 5.0 + t * 0.7 + phase), cos(uv.x * 4.0 - t * 0.6 + phase));
    vec2 a1 = vec2(0.25 + 0.18 * sin(t * 0.43 + phase), 0.30 + 0.16 * cos(t * 0.37));
    vec2 a2 = vec2(0.75 + 0.16 * cos(t * 0.31 + phase * 1.3), 0.35 + 0.20 * sin(t * 0.41 + 1.7));
    vec2 a3 = vec2(0.50 + 0.25 * sin(t * 0.27 + 2.4 + phase * 0.7), 0.80 + 0.12 * cos(t * 0.5));
    float l1 = light(w, a1, 0.10);
    float l2 = light(w, a2, 0.09);
    float l3 = light(w, a3, 0.12);
    vec3 glowCol = (c1.rgb * l1 + c2.rgb * l2 + c3.rgb * l3) / max(l1 + l2 + l3, 1e-3);
    float strength = clamp(l1 + l2 + l3, 0.0, 1.0);
    float rest = 0.16 * smoothstep(0.75, 0.0, uv.y);
    // flooded: rich but not too bright, so the light ink reads over it
    float amount = mix(rest, 0.22 + 0.38 * strength, flood) * strength + flood * 0.06;
    vec3 col = mix(base.rgb, glowCol, clamp(amount, 0.0, 1.0));
    // flooded, the edges fall away into the card's own colour
    vec2 v = uv - 0.5;
    col = mix(col, base.rgb, flood * smoothstep(0.25, 0.75, length(v * vec2(1.0, 1.3))) * 0.6);

    float sd = roundRect(p - size * 0.5, size * 0.5, radius);
    float alpha = clamp(0.5 - sd, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
