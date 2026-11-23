// glint: sileo-style desktop toasts for Hyprland/Quickshell (part of bead).
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const usage = `glint: sileo-style desktop toasts (inside bead when it runs)

usage:
  glint success|error|warning|info  TITLE [options]
  glint loading  TITLE [options]                  spinner (until --duration, or dismissed)
  glint action   TITLE --button LABEL [options]   exit 0 if the button is clicked
                 (choose/action/confirm exit 3 if the toast's body is clicked)
  glint confirm  TITLE [--yes L] [--no L]         exit 0 = yes, 1 = no / dismissed
  glint choose   TITLE -c A -c B [-c C...]        prints the chosen label; exit 1 if dismissed
  glint promise  TITLE [options] -- COMMAND...    spinner while COMMAND runs, then ✓/✗;
                                                  exits with COMMAND's status

options:
  -d, --desc TEXT        body text (the toast expands to show it)
  -p, --position POS     top-left | top-center | top-right |
                         bottom-left | bottom-center | bottom-right   (default top-center)
  -t, --duration DUR     e.g. 4s, 1500ms, 0 = until dismissed           (default 6s)
  -i, --icon ICON        custom badge icon: image path, or a glyph/emoji
  -b, --button LABEL     action button
      --yes / --no LABEL confirm buttons (default Confirm / Cancel)
  -c, --choice LABEL     choose: one button per --choice
      --grab             take keyboard focus right away (Enter/Esc answer)
      --react TYPE:TITLE after clicking the Nth button (one --react per button, in
                         order), fold up and show this pill, e.g. --react success:Allowed
      --react-label TYPE every choice reacts with its own label, e.g. ✓ SQLite
      --success TITLE    promise: title on success   (default Done)
      --error TITLE      promise: title on failure   (default Failed)
      --success-desc / --error-desc TEXT  (error defaults to the command's last stderr line)
      --fill COLOR       toast colour (default #1a1a1a)
      --roundness PX     corner radius (default 16)
      --no-expand        don't auto-expand; hover to open
      --scale N          size multiplier (default 1.15, or $TOAST_SCALE)
  -w, --wait             wait for the toast to close (success/error/warning/info/loading)
                         exit 0 if its body was clicked, 1 otherwise

Hover a toast to hold it open; swipe it up or down to dismiss.
`

type opts struct {
	kind, title, desc, position, icon, button, no, fill, roundness, scale string
	succTitle, errTitle, succDesc, errDesc                                string
	duration                                                              time.Duration
	durSet, noExpand, wait, grab                                          bool
	choices, react                                                        []string
	reactLabel                                                            string
	cmd                                                                   []string
}

func main() {
	o, err := parse(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, "glint:", err)
		fmt.Fprint(os.Stderr, "\n"+usage)
		os.Exit(2)
	}
	switch o.kind {
	case "promise":
		os.Exit(promise(o))
	case "choose":
		res := run(o, true, nil)
		if res == "clicked" {
			os.Exit(3)
		}
		if n, ok := strings.CutPrefix(res, "choice:"); ok {
			if i, err := strconv.Atoi(n); err == nil && i >= 0 && i < len(o.choices) {
				fmt.Println(o.choices[i])
				os.Exit(0)
			}
		}
		os.Exit(1)
	case "action", "confirm":
		res := run(o, true, nil)
		if res == "button" {
			os.Exit(0)
		}
		if res == "clicked" {
			os.Exit(3)
		}
		os.Exit(1)
	default:
		res := run(o, o.wait, nil)
		if o.wait && res != "clicked" {
			os.Exit(1)
		}
	}
}

func parse(args []string) (*opts, error) {
	o := &opts{position: "top-center", no: "Cancel"}
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		fmt.Print(usage)
		os.Exit(0)
	}
	o.kind = args[0]
	switch o.kind {
	case "success", "error", "warning", "info", "loading", "action", "confirm", "choose", "promise":
	default:
		return nil, fmt.Errorf("unknown type %q", o.kind)
	}
	var pos []string
	for i := 1; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			o.cmd = args[i+1:]
			break
		}
		if !strings.HasPrefix(a, "-") || a == "-" {
			pos = append(pos, a)
			continue
		}
		name, val, hasVal := strings.Cut(a, "=")
		next := func() (string, error) {
			if hasVal {
				return val, nil
			}
			if i+1 >= len(args) {
				return "", fmt.Errorf("%s needs a value", name)
			}
			i++
			return args[i], nil
		}
		var err error
		switch name {
		case "-d", "--desc", "--description":
			o.desc, err = next()
		case "-p", "--position":
			o.position, err = next()
		case "-i", "--icon":
			o.icon, err = next()
		case "-b", "--button", "--yes":
			o.button, err = next()
		case "--no":
			o.no, err = next()
		case "--fill":
			o.fill, err = next()
		case "--roundness":
			o.roundness, err = next()
		case "--scale":
			o.scale, err = next()
		case "--success":
			o.succTitle, err = next()
		case "--error":
			o.errTitle, err = next()
		case "--success-desc":
			o.succDesc, err = next()
		case "--error-desc":
			o.errDesc, err = next()
		case "-t", "--duration":
			var v string
			if v, err = next(); err == nil {
				o.duration, err = parseDur(v)
				o.durSet = true
			}
		case "-c", "--choice":
			var v string
			if v, err = next(); err == nil {
				o.choices = append(o.choices, strings.ReplaceAll(v, "\n", " "))
			}
		case "--react":
			var v string
			if v, err = next(); err == nil {
				o.react = append(o.react, v)
			}
		case "--react-label":
			o.reactLabel, err = next()
		case "--grab":
			o.grab = true
		case "--no-expand":
			o.noExpand = true
		case "-w", "--wait":
			o.wait = true
		default:
			return nil, fmt.Errorf("unknown option %s", name)
		}
		if err != nil {
			return nil, err
		}
	}
	if len(pos) == 0 {
		return nil, fmt.Errorf("missing TITLE")
	}
	o.title = strings.Join(pos, " ")
	switch o.position {
	case "top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right":
	default:
		return nil, fmt.Errorf("unknown position %q", o.position)
	}
	if o.kind == "action" && o.button == "" {
		return nil, fmt.Errorf("action needs --button LABEL")
	}
	if o.kind == "choose" && len(o.choices) == 0 {
		return nil, fmt.Errorf("choose needs at least one --choice")
	}
	if o.kind == "promise" && len(o.cmd) == 0 {
		return nil, fmt.Errorf("promise needs a command after --")
	}
	if !o.durSet {
		switch o.kind {
		case "loading", "confirm", "choose":
			o.duration = 0
		case "action":
			o.duration = 10 * time.Second
		default:
			o.duration = 6 * time.Second
		}
	}
	return o, nil
}

func parseDur(v string) (time.Duration, error) {
	if n, err := strconv.Atoi(v); err == nil { // bare number = seconds
		return time.Duration(n) * time.Second, nil
	}
	return time.ParseDuration(v)
}

// run shows one toast. With wait, it blocks and returns the toast's result
// (button / no / dismissed / timeout); otherwise it detaches and returns "".
// onLine, if set, sees every stdout line (promise uses it for TOAST_ACK).
func run(o *opts, wait bool, extraEnv []string, onLine ...func(string)) string {
	if r, ok := viaBead(o, wait, extraEnv, onLine...); ok {
		return r
	}
	// SIGPIPE ignored: once we have the result we exit while the toast plays its
	// reaction, and its later log lines must not kill it mid-animation.
	cmd := exec.Command("sh", "-c", `trap '' PIPE; exec qs -p "$0"`, qmlPath())
	cmd.Env = append(sessionEnv(),
		"TOAST_TYPE="+o.kind,
		"TOAST_TITLE="+o.title,
		"TOAST_DESC="+o.desc,
		"TOAST_POSITION="+o.position,
		"TOAST_DURATION="+strconv.FormatInt(o.duration.Milliseconds(), 10),
		"TOAST_BUTTON="+o.button,
		"TOAST_NO="+o.no,
		"TOAST_ICON="+o.icon,
		"QT_SCALE_FACTOR="+scale(o),
	)
	if o.fill != "" {
		cmd.Env = append(cmd.Env, "TOAST_FILL="+o.fill)
	}
	if o.roundness != "" {
		cmd.Env = append(cmd.Env, "TOAST_ROUNDNESS="+o.roundness)
	}
	if len(o.choices) > 0 {
		cmd.Env = append(cmd.Env, "TOAST_CHOICES="+strings.Join(o.choices, "\n"))
	}
	if o.grab {
		cmd.Env = append(cmd.Env, "TOAST_GRAB=1")
	}
	react := o.react
	if o.reactLabel != "" {
		react = nil
		for _, c := range o.choices {
			react = append(react, o.reactLabel+":"+c)
		}
	}
	if len(react) > 0 {
		cmd.Env = append(cmd.Env, "TOAST_REACT="+strings.Join(react, "\n"))
	}
	if o.noExpand {
		cmd.Env = append(cmd.Env, "TOAST_AUTOPILOT=0")
	}
	cmd.Env = append(cmd.Env, extraEnv...)
	// Own session: a Ctrl+C in the terminal must not kill the toast mid-animation.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	if !wait {
		if err := cmd.Start(); err != nil {
			die(err)
		}
		cmd.Process.Release()
		return ""
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		die(err)
	}
	if err := cmd.Start(); err != nil {
		die(err)
	}
	result := "dismissed"
	sc := bufio.NewScanner(out)
	for sc.Scan() {
		l := sc.Text()
		if _, r, ok := strings.Cut(l, "TOAST_RESULT:"); ok {
			result = strings.TrimSpace(r)
			if len(onLine) == 0 {
				return result // don't wait for the reaction animation
			}
		}
		for _, f := range onLine {
			f(l)
		}
	}
	cmd.Wait()
	return result
}

// promise shows a loading toast, runs the command (output still goes to the
// terminal), then morphs the toast into success or error.
func promise(o *opts) int {
	dir := filepath.Join(os.TempDir(), "toast")
	if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
		dir = filepath.Join(rd, "toast")
	}
	os.MkdirAll(dir, 0o700)
	state := filepath.Join(dir, fmt.Sprintf("%d.json", os.Getpid()))
	os.WriteFile(state, nil, 0o600)

	final := o.duration
	lo := *o
	lo.kind, lo.duration, lo.desc = "loading", 0, ""

	acked := make(chan struct{}, 1)
	go run(&lo, true, []string{"TOAST_STATE=" + state}, func(l string) {
		if strings.Contains(l, "TOAST_ACK") {
			select {
			case acked <- struct{}{}:
			default:
			}
		}
	})

	// Ctrl+C goes to the command (same process group); we just wait for it.
	signal.Ignore(os.Interrupt)
	c := exec.Command(o.cmd[0], o.cmd[1:]...)
	tail := &lastLine{}
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, io.MultiWriter(os.Stderr, tail)
	start := time.Now()
	err := c.Run()
	code := 0
	if err != nil {
		code = 1
		if ee, ok := err.(*exec.ExitError); ok && ee.ExitCode() > 0 {
			code = ee.ExitCode()
		}
	}

	upd := map[string]any{"duration": final.Milliseconds()}
	took := time.Since(start).Round(100 * time.Millisecond)
	if code == 0 {
		upd["type"], upd["title"] = "success", or(o.succTitle, "Done")
		upd["desc"] = o.succDesc
	} else {
		upd["type"], upd["title"] = "error", or(o.errTitle, "Failed")
		d := o.errDesc
		if d == "" {
			d = tail.String()
		}
		if d == "" {
			if err != nil && code == 1 {
				d = err.Error()
			} else {
				d = fmt.Sprintf("exited with status %d after %s", code, took)
			}
		}
		upd["desc"] = d
	}
	b, _ := json.Marshal(upd)
	// write atomically so the watcher never reads half a file
	tmp := state + ".tmp"
	os.WriteFile(tmp, b, 0o600)
	os.Rename(tmp, state)
	select {
	case <-acked:
	case <-time.After(3 * time.Second):
	}
	os.Remove(state)
	return code
}

// lastLine keeps the last non-empty line written to it.
type lastLine struct{ buf, last []byte }

func (l *lastLine) Write(p []byte) (int, error) {
	l.buf = append(l.buf, p...)
	for {
		i := bytes.IndexByte(l.buf, '\n')
		if i < 0 {
			break
		}
		if s := bytes.TrimSpace(l.buf[:i]); len(s) > 0 {
			l.last = append(l.last[:0], s...)
		}
		l.buf = l.buf[i+1:]
	}
	if len(l.buf) > 4096 {
		l.buf = l.buf[len(l.buf)-4096:]
	}
	return len(p), nil
}

func (l *lastLine) String() string {
	if s := bytes.TrimSpace(l.buf); len(s) > 0 {
		return stripANSI(string(s))
	}
	return stripANSI(string(l.last))
}

func stripANSI(s string) string {
	var b strings.Builder
	esc := false
	for _, r := range s {
		switch {
		case r == 0x1b:
			esc = true
		case esc && (r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z'):
			esc = false
		case !esc:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func qmlPath() string {
	if p := os.Getenv("TOAST_QML"); p != "" {
		return p
	}
	share := os.Getenv("XDG_DATA_HOME")
	if share == "" {
		share = filepath.Join(os.Getenv("HOME"), ".local", "share")
	}
	return filepath.Join(share, "glint", "toast.qml")
}

func scale(o *opts) string {
	return or(o.scale, os.Getenv("TOAST_SCALE"), "1.15")
}

// sessionEnv fills in the graphical session variables when toast is run from
// somewhere without them (cron, systemd units, ssh).
func sessionEnv() []string {
	env := os.Environ()
	if os.Getenv("WAYLAND_DISPLAY") != "" {
		return env
	}
	out, err := exec.Command("systemctl", "--user", "show-environment").Output()
	if err != nil {
		return env
	}
	for _, line := range strings.Split(string(out), "\n") {
		for _, k := range []string{"WAYLAND_DISPLAY=", "DISPLAY=", "XDG_RUNTIME_DIR=", "HYPRLAND_INSTANCE_SIGNATURE=", "DBUS_SESSION_BUS_ADDRESS="} {
			if strings.HasPrefix(line, k) {
				env = append(env, line)
			}
		}
	}
	return env
}

func or(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

func die(err error) {
	fmt.Fprintln(os.Stderr, "glint:", err)
	os.Exit(1)
}
