pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// System stats, polled once a second while something shows them
// (set `active`). CPU/GPU keep a short history for graphs.
Singleton {
    id: root

    property bool active: false

    property real cpu: 0
    property real gpu: 0
    property real mem: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real cpuTemp: 0
    property real gpuTemp: 0
    property real disk: 0
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property real rxRate: 0   // bytes/s
    property real txRate: 0
    property string uptime: ""
    property list<real> cores: []     // per-core load, 0–1
    property real vramUsedGb: 0
    property real vramTotalGb: 0
    readonly property real vram: vramTotalGb > 0 ? vramUsedGb / vramTotalGb : 0
    property list<real> rxHistory: []
    property list<real> txHistory: []
    property var lastCores: []
    // the busiest processes (only sampled while someone looks: procsWanted)
    property bool procsWanted: false
    property list<var> procs: []      // { pid, name, cpu (% of one core), memMb }
    property list<real> cpuHistory: []
    property list<real> gpuHistory: []
    readonly property int historyLength: 40

    property var lastCpu: null
    property var lastNet: null

    function fmtRate(b: real): string {
        if (b < 1024) return Math.round(b) + " B/s";
        if (b < 1048576) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + " KB/s";
        return (b / 1048576).toFixed(1) + " MB/s";
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.active
        onTriggered: proc.running = true
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.active && root.procsWanted
        onTriggered: if (!top.running) top.running = true
    }
    Process {
        id: top
        // the second of two quick samples: real recent CPU, not lifetime averages
        command: ["sh", "-c", "top -b -n 2 -d 0.5 -o %CPU -e m -w 512 | awk '/^top -/{n++} n==2 && $1 ~ /^[0-9]+$/ {c=$12; for(i=13;i<=NF;i++) c=c\" \"$i; print $1\"\\t\"$9\"\\t\"$6\"\\t\"c}' | head -6"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 4) continue;
                    const mem = String(f[2]);
                    const mb = mem.endsWith("g") ? parseFloat(mem) * 1024 : parseFloat(mem);
                    out.push({ pid: +f[0], cpu: parseFloat(String(f[1]).replace(",", ".")) || 0, memMb: mb || 0, name: f[3] });
                }
                root.procs = out.filter(p => p.name !== "top" && p.name !== "awk" && p.name !== "sh").slice(0, 5);
            }
        }
    }

    Process {
        id: proc
        command: ["sh", "-c", `
            grep '^cpu' /proc/stat
            for f in /sys/class/drm/card*/device/mem_info_vram_used; do [ -r "$f" ] && { echo "vram $(cat "$f") $(cat "\${f%used}total")"; break; }; done
            awk '/^(MemTotal|MemAvailable):/ {print $1, $2}' /proc/meminfo
            for f in /sys/class/drm/card*/device/gpu_busy_percent; do [ -r "$f" ] && { echo "gpu $(cat "$f")"; break; }; done
            for h in /sys/class/hwmon/hwmon*; do
                case $(cat "$h/name") in
                k10temp|coretemp) echo "cputemp $(cat "$h/temp1_input")" ;;
                amdgpu) echo "gputemp $(cat "$h/temp1_input")" ;;
                esac
            done
            df -Pk / | awk 'NR == 2 {print "disk", $3, $2}'
            awk 'NR > 2 && $1 !~ /^(lo|docker|veth|br-|virbr)/ {rx += $2; tx += $10} END {print "net", rx, tx}' /proc/net/dev | tr -d ':'
            echo "uptime $(cut -d. -f1 /proc/uptime)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                let total = 0, avail = 0;
                const now = Date.now();
                const cores = [], coreNow = [];
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (/^cpu\d+$/.test(f[0])) {
                        const v = f.slice(1, 9).map(Number);
                        const idle = v[3] + v[4], all = v.reduce((a, b) => a + b, 0);
                        const k = coreNow.length, was = root.lastCores[k];
                        cores.push(was && all > was.all ? 1 - (idle - was.idle) / (all - was.all) : 0);
                        coreNow.push({ all: all, idle: idle });
                        continue;
                    }
                    switch (f[0]) {
                    case "vram": root.vramUsedGb = +f[1] / 1073741824; root.vramTotalGb = +f[2] / 1073741824; break;
                    case "cpu": {
                        const v = f.slice(1, 9).map(Number);
                        const idle = v[3] + v[4], all = v.reduce((a, b) => a + b, 0);
                        if (root.lastCpu && all > root.lastCpu.all)
                            root.cpu = 1 - (idle - root.lastCpu.idle) / (all - root.lastCpu.all);
                        root.lastCpu = { all: all, idle: idle };
                        break;
                    }
                    case "MemTotal:": total = +f[1]; break;
                    case "MemAvailable:": avail = +f[1]; break;
                    case "gpu": root.gpu = +f[1] / 100; break;
                    case "cputemp": root.cpuTemp = +f[1] / 1000; break;
                    case "gputemp": root.gpuTemp = +f[1] / 1000; break;
                    case "disk":
                        root.disk = +f[1] / Math.max(1, +f[2]);
                        root.diskUsedGb = +f[1] / 1048576;
                        root.diskTotalGb = +f[2] / 1048576;
                        break;
                    case "net": {
                        const rx = +f[1], tx = +f[2];
                        if (root.lastNet) {
                            const dt = Math.max(0.2, (now - root.lastNet.t) / 1000);
                            root.rxRate = Math.max(0, (rx - root.lastNet.rx) / dt);
                            root.txRate = Math.max(0, (tx - root.lastNet.tx) / dt);
                        }
                        root.lastNet = { rx: rx, tx: tx, t: now };
                        break;
                    }
                    case "uptime": {
                        const s = +f[1], d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                        root.uptime = (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m";
                        break;
                    }
                    }
                }
                if (total > 0) {
                    root.mem = 1 - avail / total;
                    root.memUsedGb = (total - avail) / 1048576;
                    root.memTotalGb = total / 1048576;
                }
                if (coreNow.length) { root.cores = cores; root.lastCores = coreNow; }
                root.rxHistory = [...root.rxHistory, root.rxRate].slice(-root.historyLength);
                root.txHistory = [...root.txHistory, root.txRate].slice(-root.historyLength);
                root.cpuHistory = [...root.cpuHistory, root.cpu].slice(-root.historyLength);
                root.gpuHistory = [...root.gpuHistory, root.gpu].slice(-root.historyLength);
            }
        }
    }
}
