#version 440
// The welcome intro's bead (modules/welcome/Welcome.qml): a rounded rectangle
// with a soft halo that, as it reaches the top of the screen, joins the
// frame's edge the way the island does (shaders/goo.frag): concave rounded
// fillets where they meet. Of the frame's strip only the bead's own column is
// drawn: the rest of the edge comes with the comets (shaders/trace.frag).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 pill;      // the bead (x, y, w, h)
    float radius;   // its corners (clamped to half its size)
    float fillet;   // the join's fillets
    float wallH;    // the frame's top strip, 0 → wallH
    vec4 fill;
    vec4 glow;      // a = strength
};

float sdRoundBox(vec2 p, vec4 r, float rad) {
    vec2 c = r.xy + r.zw * 0.5;
    vec2 h = r.zw * 0.5;
    rad = min(rad, min(h.x, h.y));
    vec2 q = abs(p - c) - h + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

// exact union with circular fillets of radius r (hg_sdf fOpUnionRound)
float roundUnion(float a, float b, float r) {
    vec2 u = max(vec2(r - a, r - b), vec2(0.0));
    return max(r, min(a, b)) - length(u);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float dp = sdRoundBox(p, pill, radius);
    float dw = p.y - wallH;                    // the strip: y < wallH
    float d = roundUnion(dp, dw, fillet);
    float a = clamp(0.5 - d, 0.0, 1.0);
    if (p.y < wallH) {
        // in the strip, only the bead's own span (it runs up into the frame
        // like the island); the colour flowing round the frame
        // (shaders/trace.frag) starts from its ends
        // out to where the fillets meet the edge, so nothing's missing above them
        float dx = abs(p.x - (pill.x + pill.z * 0.5)) - pill.z * 0.5 - fillet;
        a = clamp(0.5 - dx, 0.0, 1.0) * clamp(0.5 - (pill.y - p.y), 0.0, 1.0);
    }
    vec4 col = fill * a;
    // the halo, round the bead only (not the strip)
    float below = smoothstep(wallH, wallH + 8.0, p.y);
    float g = glow.a * pow(1.0 - smoothstep(0.0, 22.0, dp), 2.0) * below * (1.0 - a);
    col += vec4(glow.rgb, 1.0) * g;
    fragColor = col * qt_Opacity;
}
