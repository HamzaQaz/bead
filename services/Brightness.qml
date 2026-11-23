pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Monitor brightness over DDC/CI (ddcutil). change() updates the shown value at
// once and writes it in the background; key repeats are coalesced, so at most
// one write per monitor is in flight and the last value always wins.
Singleton {
    id: root

    signal changed(string screenName, real value)

    property var buses: ({})    // connector ("DP-1") -> i2c bus number
    property var values: ({})   // connector -> 0..1
    property var pending: ({})  // connector -> percent waiting to be written
    property var busy: ({})

    function has(screen: ShellScreen): bool { return buses[screen?.name ?? ""] !== undefined; }
    function value(screen: ShellScreen): real { return values[screen?.name ?? ""] ?? 0.5; }

    function change(screen: ShellScreen, deltaPct: real): void {
        set(screen, value(screen) + deltaPct / 100);
    }

    function set(screen: ShellScreen, v: real): void {
        const name = screen?.name ?? "";
        if (buses[name] === undefined) return; // no DDC for this monitor
        v = Math.max(0, Math.min(1, v));
        values = Object.assign({}, values, { [name]: v }); // reassign: bindings update
        changed(name, v);
        pending[name] = Math.round(v * 100);
        if (!busy[name]) write(name);
    }

    function write(name: string): void {
        const value = pending[name];
        if (value === undefined) return;
        delete pending[name];
        busy[name] = true;
        setter.createObject(root, { name: name, bus: buses[name], value: value });
    }

    Component {
        id: setter
        Process {
            property string name
            property int bus
            property int value
            command: ["ddcutil", "--bus", String(bus), "--noverify", "setvcp", "10", String(value)]
            running: true
            onExited: {
                root.busy[name] = false;
                root.write(name); // a newer value arrived meanwhile
                destroy();
            }
        }
    }

    // initial values: "VCP 10 C <current> <max>"
    Component {
        id: getter
        Process {
            property string name
            property int bus
            command: ["ddcutil", "--bus", String(bus), "getvcp", "10", "--brief"]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/VCP 10 C (\d+) (\d+)/);
                    if (m) root.values = Object.assign({}, root.values, { [name]: parseInt(m[1]) / Math.max(1, parseInt(m[2])) });
                }
            }
            onExited: destroy()
        }
    }

    // which i2c bus drives which connector
    Process {
        command: ["ddcutil", "detect", "--brief"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const block of text.split(/\n\s*\n/)) {
                    const bus = block.match(/I2C bus:\s*\/dev\/i2c-(\d+)/);
                    const conn = block.match(/DRM connector:\s*card\d+-(\S+)/);
                    if (bus && conn && !/Invalid display/.test(block)) map[conn[1]] = parseInt(bus[1]);
                }
                root.buses = map;
                for (const name in map) getter.createObject(root, { name: name, bus: map[name] });
            }
        }
    }
}
