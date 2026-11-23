#version 440
// One gooey shape for a whole stack of pills: the screen frame (everything
// outside a rounded rectangle, like Caelestia's border) smooth-merged with up
// to 8 pills and their bodies, so they grow out of the frame and melt into it
// and into each other. Rects are (x, y, w, h) in item pixels; w <= 0 = unused.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 inner;        // the frame's inner rounded rect (the hole)
    float innerRadius;
    float radius;
    float goo;
    vec4 fill;
    vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6; vec4 p7;
    vec4 b0; vec4 b1; vec4 b2; vec4 b3; vec4 b4; vec4 b5; vec4 b6; vec4 b7;
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

float addPill(float d, vec2 p, vec4 pr, vec4 br) {
    if (pr.z <= 0.0) return d;
    d = smin(d, sdRoundBox(p, pr, radius), goo);
    // a thin body melts away gradually instead of popping
    float fadeH = goo * 0.6;
    if (br.z > 0.0)
        d = smin(d, sdRoundBox(p, br, radius) + max(fadeH - br.w, 0.0) * 2.0, goo);
    return d;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = -sdRoundBox(p, inner, innerRadius); // the frame
    d = addPill(d, p, p0, b0); d = addPill(d, p, p1, b1);
    d = addPill(d, p, p2, b2); d = addPill(d, p, p3, b3);
    d = addPill(d, p, p4, b4); d = addPill(d, p, p5, b5);
    d = addPill(d, p, p6, b6); d = addPill(d, p, p7, b7);
    float a = clamp(0.5 - d, 0.0, 1.0);
    fragColor = fill * a * qt_Opacity;
}
