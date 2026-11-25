#version 440
// The welcome intro's stage (modules/welcome/Welcome.qml), in one pass:
// - the screen's frame (bar included) fills with the island's colour, flowing
//   out from the island both ways round, with a soft liquid front (trace)
// - the colour settles into the frame's own (settle), then the whole layer
//   gives way to the real frame and bar underneath (fade)
// - the dark over the screen lifts in a circle spreading from the island (lift)
// Coordinates are item pixels.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 inner;     // the frame's inner edge (x, y, w, h)
    float radius;   // its corners
    float trace;    // 0 → 1: how far round the colour has flowed
    float settle;   // 0 → 1: the island's colour → the frame's
    float fade;     // 0 → 1: this layer → the real frame
    float dark;     // 1 black (off once the intro's done)
    float lift;     // 0 → 1: the dark's circle grows from the island
    vec2 origin;    // the island
    float span;     // half the island's width, with its fillets: the flow starts there
    vec4 accent;
    vec4 frame;
};

float sdRoundBox(vec2 p, vec4 r, float rad) {
    vec2 c = r.xy + r.zw * 0.5;
    vec2 h = r.zw * 0.5;
    vec2 q = abs(p - c) - h + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

// how far along its side's path (0 at the island, 1 at the bottom centre) the
// edge nearest p is; each side normalised by its own length, so both arrive
// together
float along(vec2 p) {
    float cx = origin.x;
    bool right = p.x >= cx;
    float side = right ? inner.x + inner.z : inner.x;
    float a = max(abs(side - cx) - span, 1.0);   // from the island's end
    float h = inner.w;
    float top = inner.y, bottom = inner.y + inner.w;
    float dt = abs(p.y - top), ds = abs(p.x - side), db = abs(p.y - bottom);
    float s;
    if (ds < dt && ds < db) s = a + clamp(p.y - top, 0.0, h);
    else if (dt <= db) s = clamp(abs(p.x - cx) - span, 0.0, a);
    else s = a + h + (a - clamp(abs(p.x - cx) - span, 0.0, a));
    return s / (2.0 * a + h);
}

void main() {
    vec2 p = qt_TexCoord0 * size;

    float d = sdRoundBox(p, inner, radius);   // > 0 in the frame
    float inFrame = smoothstep(-0.5, 0.5, d);

    // the dark over the screen, with a soft hole growing from the island
    float far = length(size) * 1.1;
    float R = lift * far;
    float hole = smoothstep(R - 260.0, R, distance(p, origin));
    float black = dark * hole;

    // the frame: filled where the colour has reached, with a soft front
    float u = along(p);
    float filled = 1.0 - smoothstep(trace - 0.025, trace, u);
    if (trace >= 1.0) filled = 1.0;
    vec3 c = mix(accent.rgb, frame.rgb, settle);
    // a little brighter right at the front, like a wave
    float front = filled * smoothstep(trace - 0.08, trace, u) * (1.0 - settle);
    c = mix(c, min(vec3(1.0), accent.rgb * 1.25), front * 0.6);
    // in the frame: the colour where it's reached (fading to the real frame),
    // the dark where it hasn't yet
    float fa = filled * (1.0 - fade);
    vec4 frameCol = vec4(c, 1.0) * fa + vec4(0.0, 0.0, 0.0, 1.0) * dark * (1.0 - filled);

    // a soft glow of the colour on the screen side of its inner edge
    float glow = (d < 0.0 ? exp(d / 10.0) : 0.0) * 0.35 * filled * (1.0 - settle) * (1.0 - fade);

    vec4 screenCol = vec4(0.0, 0.0, 0.0, 1.0) * black;
    screenCol = vec4(accent.rgb, 1.0) * glow + screenCol * (1.0 - glow);

    fragColor = mix(screenCol, frameCol, inFrame) * qt_Opacity;
}
