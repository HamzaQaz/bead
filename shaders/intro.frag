#version 440
// The welcome card's backdrop: three of the theme's colours drifting as soft
// lights over the card's own colour. `flood` 1 lets them cover the card (the
// intro, while "bead." is written over it); 0 leaves a faint glow at the top.
// `phase` shifts where they sit (it moves with each step, so pages drift into
// one another). `gather` 0 → 1 draws the lights together into one small bright
// point at `target` (in 0–1 of the card), where the intro's bead is born.
// The intro adds two things over that: an aurora hanging from the top edge
// in the same colours (`aurora` 0 → 1), and a field of small dots (`dots` its
// opacity) spreading out from `origin` (px; `grid` 0 → 1 how far it has got),
// with a ripple of light running out through it from there (`wave` 0 → 1)
// that swells and colours each dot it passes. A fine grain sits over the
// light. The card's rounded corners are cut here too (`radius`).

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
    vec2 target;
    float gather;
    vec2 origin;
    float aurora;
    float grid;
    float dots;
    float wave;
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
    // gathering: each light slides to the target (the far ones a little later)
    // and tightens; at the very end they're gone, the bead takes over
    float g1 = smoothstep(0.0, 0.85, gather), g2 = smoothstep(0.08, 0.92, gather), g3 = smoothstep(0.14, 1.0, gather);
    a1 = mix(a1, target, g1); a2 = mix(a2, target, g2); a3 = mix(a3, target, g3);
    vec2 aspect = mix(vec2(1.0), vec2(size.x / size.y, 1.0), gather); // round, once small
    float fade = 1.0 - smoothstep(0.88, 1.0, gather);
    float l1 = light(w * aspect, a1 * aspect, 0.10 * mix(1.0, 0.012, g1 * g1)) * fade;
    float l2 = light(w * aspect, a2 * aspect, 0.09 * mix(1.0, 0.012, g2 * g2)) * fade;
    float l3 = light(w * aspect, a3 * aspect, 0.12 * mix(1.0, 0.012, g3 * g3)) * fade;
    vec3 glowCol = (c1.rgb * l1 + c2.rgb * l2 + c3.rgb * l3) / max(l1 + l2 + l3, 1e-3);
    float strength = clamp(l1 + l2 + l3, 0.0, 1.0);
    float rest = 0.16 * smoothstep(0.75, 0.0, uv.y);
    // flooded: rich but not too bright, so the light ink reads over it
    float amount = mix(rest, 0.22 + 0.38 * strength, flood) * strength + flood * 0.06;
    vec3 col = mix(base.rgb, glowCol, clamp(amount, 0.0, 1.0));
    // flooded, the edges fall away into the card's own colour
    vec2 v = uv - 0.5;
    col = mix(col, base.rgb, flood * smoothstep(0.25, 0.75, length(v * vec2(1.0, 1.3))) * 0.6);

    // the aurora: a curtain from the top with a wavy hem, brightest along the
    // hem, in fine upright rays, its colour running across the card
    vec3 ramp = uv.x < 0.5 ? mix(c1.rgb, c2.rgb, uv.x * 2.0) : mix(c2.rgb, c3.rgb, uv.x * 2.0 - 1.0);
    float hem = 0.50 + 0.15 * (sin(uv.x * 3.1 + t * 0.45) * 0.55 + sin(uv.x * 7.7 - t * 0.6 + 1.3) * 0.3 + sin(uv.x * 13.0 + t * 0.9) * 0.15);
    float curtain = smoothstep(hem + 0.20, hem - 0.10, uv.y) * exp(-max(hem - uv.y, 0.0) * 2.4);
    float rays = 0.72 + 0.28 * sin(uv.x * 46.0 + sin(uv.x * 9.0 + t * 0.5) * 3.0 + t * 0.7);
    float au = curtain * rays * aurora;
    col = mix(col, ramp, clamp(au * 0.75, 0.0, 1.0)) + ramp * au * 0.28;
    amount = max(amount, au);

    // the dots: a grid with one of them exactly on the origin
    float cell = 22.0;
    vec2 g = mod(p - origin + cell * 0.5, cell) - cell * 0.5;
    float away = length(p - g - origin);
    float reach = length(size);
    float shown = smoothstep(grid * reach, grid * reach - 80.0, away) * step(0.001, grid);
    float lit = exp(-pow((away - wave * reach * 0.85) / (36.0 + 70.0 * wave), 2.0)) * (1.0 - wave * 0.75) * step(0.001, wave);
    float dotA = clamp(1.1 + 3.0 * lit - length(g) + 0.5, 0.0, 1.0) * shown * dots;
    col = mix(col, mix(vec3(1.0), ramp, 0.55), dotA * (0.24 + 0.76 * lit));

    // a fine grain over the light, like film
    float grain = fract(sin(dot(p + fract(t) * 61.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    col += grain * 0.05 * clamp(amount * 2.0, 0.0, 1.0);

    float sd = roundRect(p - size * 0.5, size * 0.5, radius);
    float alpha = clamp(0.5 - sd, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
