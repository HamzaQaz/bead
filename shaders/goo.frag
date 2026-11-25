#version 440
// Gooey merge of two rounded rectangles (pill + body) via signed distance
// fields and a smooth minimum, with a soft drop shadow. Coordinates are in
// item pixels; rects are (x, y, w, h).
// Optional `wall` (w > 0): a square-edged strip (the screen frame) the shape
// joins with clean rounded fillets, so it grows out of the edge of the screen.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 pill;
    vec4 body;
    vec4 wall;
    float radius;
    float goo;
    vec4 fill;
    vec4 shadow;
    vec4 glow;   // a coloured halo round the pill only (not the wall); a = strength
};

float sdRoundBox(vec2 p, vec4 r, float rad) {
    vec2 c = r.xy + r.zw * 0.5;
    vec2 h = r.zw * 0.5;
    rad = min(rad, min(h.x, h.y));
    vec2 q = abs(p - c) - h + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// exact union with circular fillets of radius r (hg_sdf fOpUnionRound): clean
// concave corners where a shape meets the screen frame, like Caelestia's drawers
float roundUnion(float a, float b, float r) {
    vec2 u = max(vec2(r - a, r - b), vec2(0.0));
    return max(r, min(a, b)) - length(u);
}

float shape(vec2 p) {
    float d = sdRoundBox(p, pill, radius);
    // Like sileo's blur+threshold, a thin body must melt away gradually rather
    // than stay solid and vanish in one frame: push its field outward as it
    // gets thinner, so at height 0 it is beyond the goo range (no pop).
    float fadeH = goo * 0.6;
    float db = sdRoundBox(p, body, radius) + max(fadeH - body.w, 0.0) * 2.0;
    d = smin(d, db, goo);
    if (wall.z > 0.0) d = roundUnion(d, sdRoundBox(p, wall, 0.0), radius * 0.75);
    return d;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = shape(p);
    float a = clamp(0.5 - d, 0.0, 1.0); // 1px antialiased edge

    float sd = shape(p - vec2(0.0, 4.0));
    float s = shadow.a * (1.0 - smoothstep(-6.0, 14.0, sd));

    vec4 col = fill * a;                    // premultiplied
    col += vec4(shadow.rgb, 1.0) * s * (1.0 - a);

    // the halo: falls off over ~20px from the pill, kept off the wall strip
    float gd = sdRoundBox(p, pill, radius);
    // and round the body too, when there is one (the welcome intro's bead)
    if (body.z > 0.0 && body.w > 0.0) gd = smin(gd, sdRoundBox(p, body, radius), goo);
    float below = wall.z > 0.0 ? smoothstep(wall.w, wall.w + 8.0, p.y) : 1.0;
    float g = glow.a * pow(1.0 - smoothstep(0.0, 22.0, gd), 2.0) * below * (1.0 - a);
    col += vec4(glow.rgb, 1.0) * g;
    fragColor = col * qt_Opacity;
}
