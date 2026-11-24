package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// viaBead shows the toast inside the running bead shell (its notification stack),
// so toasts and notifications share one place. It reports ok=false when bead
// isn't running (or TOAST_BEAD=0), and the caller falls back to a standalone toast.
//
// Protocol: `qs -p <bead> ipc call toast push <spec json>`; bead writes the outcome
// to $XDG_RUNTIME_DIR/bead/toast/<id>.result (a button id, "dismissed" or
// "timeout"), and <id>.ack after applying a promise state update.
func viaBead(o *opts, wait bool, extraEnv []string, onLine ...func(string)) (string, bool) {
	if os.Getenv("TOAST_BEAD") == "0" {
		return "", false
	}
	share := filepath.Join(or(os.Getenv("XDG_DATA_HOME"), filepath.Join(os.Getenv("HOME"), ".local/share")), "bead")
	if _, err := os.Stat(filepath.Join(share, "shell.qml")); err != nil {
		return "", false
	}

	id := fmt.Sprintf("%d-%d", os.Getpid(), time.Now().UnixNano())
	spec := map[string]any{
		"id":       id,
		"type":     o.kind,
		"title":    o.title,
		"desc":     o.desc,
		"duration": o.duration.Milliseconds(),
		"icon":     expandHome(o.icon),
		"buttons":  beadButtons(o),
	}
	if o.questions != "" {
		var qs any
		if json.Unmarshal([]byte(o.questions), &qs) == nil {
			spec["questions"] = qs
		}
	}
	if o.noExpand {
		spec["autopilot"] = false
	}
	for _, e := range extraEnv {
		if v, ok := strings.CutPrefix(e, "TOAST_STATE="); ok {
			spec["state"] = v
		}
	}
	b, _ := json.Marshal(spec)

	dir := filepath.Join(or(os.Getenv("XDG_RUNTIME_DIR"), os.TempDir()), "bead", "toast")
	result, ack := filepath.Join(dir, id+".result"), filepath.Join(dir, id+".ack")
	out, err := exec.Command("qs", "-p", share, "ipc", "call", "toast", "push", string(b)).Output()
	if err != nil || strings.TrimSpace(string(out)) != id {
		return "", false
	}
	if !wait {
		return "", true
	}

	alive := time.Now()
	for {
		if _, err := os.Stat(ack); err == nil {
			os.Remove(ack)
			for _, f := range onLine {
				f("TOAST_ACK")
			}
		}
		if r, err := os.ReadFile(result); err == nil {
			os.Remove(result)
			return strings.TrimSpace(string(r)), true
		}
		// bead gone (crashed, restarted): don't wait forever
		if time.Since(alive) > 3*time.Second {
			if exec.Command("qs", "-p", share, "ipc", "call", "toast", "ping").Run() != nil {
				return "dismissed", true
			}
			alive = time.Now()
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// beadButtons mirrors the standalone toast's buttons and reactions.
func beadButtons(o *opts) []map[string]string {
	react := o.react
	if o.reactLabel != "" {
		react = nil
		for _, c := range o.choices {
			react = append(react, o.reactLabel+":"+c)
		}
	}
	at := func(i int) string {
		if i < len(react) {
			return react[i]
		}
		return ""
	}
	var bs []map[string]string
	switch o.kind {
	case "choose":
		for i, c := range o.choices {
			bs = append(bs, map[string]string{"id": fmt.Sprintf("choice:%d", i), "label": c, "react": at(i)})
		}
	case "confirm":
		bs = append(bs,
			map[string]string{"id": "button", "label": or(o.button, "Confirm"), "react": at(0)},
			map[string]string{"id": "no", "label": or(o.no, "Cancel"), "react": at(1)})
	case "action":
		if o.button != "" {
			bs = append(bs, map[string]string{"id": "button", "label": o.button, "react": at(0)})
		}
	}
	return bs
}

func expandHome(p string) string {
	if rest, ok := strings.CutPrefix(p, "~/"); ok {
		return filepath.Join(os.Getenv("HOME"), rest)
	}
	return p
}
