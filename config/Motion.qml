pragma Singleton

import QtQuick
import Quickshell
import "look.js" as L

// sileo's motion: a slightly bouncy spring (--sileo-spring-easing, sampled as CSS
// linear()) and a bounce-free settle used when things close.
Singleton {
    // Customise → Motion: speed, bounce, or none at all
    readonly property int dur: L.duration(600, Look.v)
    readonly property bool on: Look.v.motionOn
    readonly property real bounce: Look.v.bounce
    // any animation's length, at the chosen speed (1 ms with animations off)
    function ms(base: real): int { return L.duration(base, Look.v); }

    readonly property var curve: [
        [0, 0], [0.006, 0.002], [0.012, 0.007], [0.018, 0.015], [0.024, 0.026], [0.031, 0.041],
        [0.038, 0.06], [0.053, 0.108], [0.066, 0.157], [0.08, 0.214], [0.137, 0.467], [0.163, 0.577],
        [0.177, 0.631], [0.191, 0.682], [0.205, 0.73], [0.218, 0.771], [0.231, 0.808], [0.245, 0.844],
        [0.258, 0.874], [0.272, 0.903], [0.286, 0.928], [0.301, 0.952], [0.316, 0.972], [0.331, 0.988],
        [0.357, 1.01], [0.385, 1.025], [0.416, 1.034], [0.45, 1.038], [0.501, 1.035], [0.642, 1.012],
        [0.73, 1.003], [0.837, 0.999], [1, 1]
    ]

    function spring(t: real): real {
        if (t <= 0) return 0;
        if (t >= 1) return 1;
        return bounce === 1 ? sileo(t) : L.blend(sileo(t), settle(t), bounce);
    }
    function sileo(t: real): real {
        if (t <= 0) return 0;
        if (t >= 1) return 1;
        for (let i = 1; i < curve.length; i++) {
            const p1 = curve[i];
            if (t <= p1[0]) {
                const p0 = curve[i - 1];
                return p0[1] + (p1[1] - p0[1]) * (t - p0[0]) / (p1[0] - p0[0]);
            }
        }
        return 1;
    }

    function settle(t: real): real {
        if (t >= 1) return 1;
        const w = 7.5, e = x => 1 - (1 + w * x) * Math.exp(-w * x);
        return e(t) / e(1);
    }
}
