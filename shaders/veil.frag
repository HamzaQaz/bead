#version 440
// The welcome's dimmed room (modules/welcome/Welcome.qml): the screen inside
// the frame, but not the frame, the bar or the island, which stay as they are
// (so the intro's sketch of them hands over without a change).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 inner;     // the frame's inner edge (x, y, w, h)
    float radius;   // its corners
    vec4 island;    // the island's pill (x, y, w, h), its top in the frame's strip
    float fillet;   // where it joins the edge
    vec4 color;     // premultiplied by the caller's alpha
};

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

void main() {
    vec2 p = qt_TexCoord0 * size;
    // the frame with the island hanging from it: the room is everything else
    float frame = -sdRoundBox(p, inner, radius);
    float isl = roundUnion(sdRoundBox(p, island, 17.0), p.y - inner.y, fillet);
    float d = min(frame, isl);
    float room = clamp(d + 0.5, 0.0, 1.0);
    fragColor = color * room * qt_Opacity;
}
