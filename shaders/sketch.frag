#version 440
// The welcome intro's bar (modules/welcome/Welcome.qml), drawn from a capture
// of the real one taken as the intro starts: it appears as the colour flows
// down past it (shaders/trace.frag), in the flowing colour's shades, then
// settles into exactly the real bar's (and island's) pixels, so the handover
// can't be seen.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float barW;     // the bar's width (the frame's left side)
    float wallW;    // the frame's thickness
    float aL;       // the flow's path along the top, from the island to the corner
    float trace;    // 0 → 1: how far the flow has gone
    float settle;   // 0 → 1: the flowing colour → the real bar
    vec4 pill;      // the island's pill as the intro draws it (x, y, w, h)
    float radius;   // its corners
    float fillet;   // its join to the edge
    float island;   // 1 once it's landed: it's drawn from the capture too
    vec4 accent;
    vec4 ink;       // the deepest shade (the bead's face)
    vec4 frame;
    vec4 text;
};
layout(binding = 1) uniform sampler2D src;

float sdRoundBox(vec2 p, vec4 r, float rad) {
    vec2 c = r.xy + r.zw * 0.5;
    vec2 h = r.zw * 0.5;
    rad = min(rad, min(h.x, h.y));
    vec2 q = abs(p - c) - h + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

float roundUnion(float a, float b, float r) {
    vec2 u = max(vec2(r - a, r - b), vec2(0.0));
    return max(r, min(a, b)) - length(u);
}

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
    vec2 p = qt_TexCoord0 * size;
    float shown;
    if (p.x < barW) {
        // the bar, where the flow is down the left side (trace.frag: along())
        float u = (aL + (p.y - wallW)) / (2.0 * aL + size.y - 2.0 * wallW);
        shown = smoothstep(u, u + 0.03, trace);
    } else {
        // the island: its pill joined to the edge, as rise.frag draws it
        float d = roundUnion(sdRoundBox(p, pill, radius), p.y - wallW, fillet);
        float a = clamp(0.5 - d, 0.0, 1.0);
        if (p.y < wallW) {
            float dx = abs(p.x - (pill.x + pill.z * 0.5)) - pill.z * 0.5 - fillet;
            a = clamp(0.5 - dx, 0.0, 1.0) * clamp(0.5 - (pill.y - p.y), 0.0, 1.0);
        }
        shown = a * island;
    }
    if (shown <= 0.0) { fragColor = vec4(0.0); return; }
    vec3 c = texture(src, qt_TexCoord0).rgb;
    // the real bar in the flowing colour: its background the colour itself, what's
    // on it (lighter than the background) in deeper shades of it
    float m = clamp((lum(c) - lum(frame.rgb)) / max(lum(text.rgb) - lum(frame.rgb), 0.05), -0.4, 1.0);
    vec3 tinted = m >= 0.0 ? mix(accent.rgb, ink.rgb, m) : mix(accent.rgb, vec3(1.0), -m);
    vec3 col = mix(tinted, c, settle);
    // opaque to the end: what's under it fades unseen, and it goes when it's
    // become exactly what's under it
    fragColor = vec4(col, 1.0) * shown * qt_Opacity;
}
