package main

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── look ──

var (
	accent = lipgloss.AdaptiveColor{Light: "#5b5fa8", Dark: "#b3baeb"}
	dim    = lipgloss.AdaptiveColor{Light: "#7a7a8c", Dark: "#8a8ca3"}
	good   = lipgloss.AdaptiveColor{Light: "#2f8a4f", Dark: "#86d6a0"}
	bad    = lipgloss.AdaptiveColor{Light: "#b3363a", Dark: "#f2949a"}
	warn   = lipgloss.AdaptiveColor{Light: "#9a6a00", Dark: "#f1cf7a"}

	sTitle = lipgloss.NewStyle().Foreground(accent).Bold(true)
	sDim   = lipgloss.NewStyle().Foreground(dim)
	sGood  = lipgloss.NewStyle().Foreground(good)
	sBad   = lipgloss.NewStyle().Foreground(bad)
	sWarn  = lipgloss.NewStyle().Foreground(warn)
	sAcc   = lipgloss.NewStyle().Foreground(accent)
	sKey   = lipgloss.NewStyle().Foreground(accent).Bold(true)
	sFrame = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(accent).Padding(1, 3)
)

const logo = `  ●  bead`

// the strand: one bead per step, filled as they're threaded on
func strandBar(done, total, failed int) string {
	var b strings.Builder
	b.WriteString(sDim.Render("─"))
	for i := 0; i < total; i++ {
		switch {
		case i == failed:
			b.WriteString(sBad.Render("●"))
		case i < done:
			b.WriteString(sAcc.Render("●"))
		case i == done:
			b.WriteString(sAcc.Render("◌"))
		default:
			b.WriteString(sDim.Render("○"))
		}
		b.WriteString(sDim.Render("─"))
	}
	return b.String()
}

// ── model ──

type screen int

const (
	welcome screen = iota
	pickParts
	pickPearl
	enterKey
	review
	running
	finished
)

type stepState struct {
	step
	status string // "" | ok | fail | skip
	note   string
}

type model struct {
	sys    system
	dry    bool
	parts  []*part
	screen screen
	cursor int
	pearl  int
	key    textinput.Model
	spin   spinner.Model

	steps             []stepState
	repoPkgs, aurPkgs []string
	downloadMB        int
	at                int // the step running now
	failed            int // -1, or the failed step
	width             int
	quitting          bool
}

type stepDone struct {
	out string
	err error
}

func newModel(s system, dry bool) model {
	ti := textinput.New()
	ti.Placeholder = "sk-ant-…"
	ti.EchoMode = textinput.EchoPassword
	ti.EchoCharacter = '•'
	ti.Width = 48
	sp := spinner.New()
	sp.Spinner = spinner.MiniDot
	sp.Style = sAcc
	m := model{sys: s, dry: dry, parts: allParts(), key: ti, spin: sp, failed: -1}
	for _, p := range m.parts {
		if p.id == "glint-claude" {
			p.on = s.claude
			if !s.claude {
				p.disable = "Claude Code isn't installed"
			}
		}
	}
	return m
}

func (m model) Init() tea.Cmd { return nil }

func (m model) chosen() choices {
	c := choices{parts: map[string]bool{}, pearl: pearlWays[m.pearl].id, apiKey: m.key.Value()}
	byID := map[string]*part{}
	for _, p := range m.parts {
		byID[p.id] = p
	}
	for _, p := range m.parts {
		if p.on && p.disable == "" && (p.needs == "" || byID[p.needs].on) {
			c.parts[p.id] = true
		}
	}
	return c
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spin, cmd = m.spin.Update(msg)
		return m, cmd
	case stepDone:
		return m.finishStep(msg)
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			m.quitting = true
			return m, tea.Quit
		}
		return m.key_(msg)
	}
	return m, nil
}

func (m model) key_(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	switch m.screen {
	case welcome:
		switch s {
		case "enter":
			if !m.sys.arch {
				return m, nil
			}
			m.screen = pickParts
		case "q", "esc":
			m.quitting = true
			return m, tea.Quit
		}
	case pickParts:
		switch s {
		case "up", "k":
			m.cursor = (m.cursor + len(m.parts) - 1) % len(m.parts)
		case "down", "j":
			m.cursor = (m.cursor + 1) % len(m.parts)
		case " ", "x":
			p := m.parts[m.cursor]
			if !p.core && p.disable == "" {
				p.on = !p.on
			}
		case "enter":
			if m.chosen().has("pearl") {
				m.screen = pickPearl
			} else {
				return m.toReview()
			}
		case "esc", "b":
			m.screen = welcome
		case "q":
			m.quitting = true
			return m, tea.Quit
		}
	case pickPearl:
		switch s {
		case "up", "k":
			m.pearl = (m.pearl + len(pearlWays) - 1) % len(pearlWays)
		case "down", "j":
			m.pearl = (m.pearl + 1) % len(pearlWays)
		case "enter":
			if pearlWays[m.pearl].id == "local" && !m.chosen().has("murmur") {
				// the local model is Murmur's: pull it in
				for _, p := range m.parts {
					if p.id == "murmur" {
						p.on = true
					}
				}
			}
			if pearlWays[m.pearl].id == "api" {
				m.screen = enterKey
				return m, m.key.Focus()
			}
			return m.toReview()
		case "esc", "b":
			m.screen = pickParts
		}
	case enterKey:
		switch s {
		case "enter":
			m.key.Blur()
			return m.toReview()
		case "esc":
			m.key.Blur()
			m.screen = pickPearl
			return m, nil
		}
		var cmd tea.Cmd
		m.key, cmd = m.key.Update(k)
		return m, cmd
	case review:
		switch s {
		case "enter", "y":
			m.screen = running
			m.at = 0
			return m, tea.Batch(m.spin.Tick, m.runStep())
		case "esc", "b":
			m.screen = pickParts
		case "q":
			m.quitting = true
			return m, tea.Quit
		}
	case running:
		if m.failed < 0 {
			return m, nil
		}
		switch s {
		case "r": // retry
			m.steps[m.failed].status = ""
			m.at, m.failed = m.failed, -1
			return m, m.runStep()
		case "s": // skip
			m.steps[m.failed].status = "skip"
			m.at, m.failed = m.failed+1, -1
			if m.at >= len(m.steps) {
				m.screen = finished
				return m, nil
			}
			return m, m.runStep()
		case "q":
			m.quitting = true
			return m, tea.Quit
		}
	case finished:
		if s == "enter" || s == "q" || s == "esc" {
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) toReview() (tea.Model, tea.Cmd) {
	steps, repo, aur, mb := plan(m.sys, m.parts, m.chosen())
	m.steps = m.steps[:0]
	for _, st := range steps {
		m.steps = append(m.steps, stepState{step: st})
	}
	m.repoPkgs, m.aurPkgs, m.downloadMB = repo, aur, mb
	m.screen = review
	return m, nil
}

func (m model) runStep() tea.Cmd {
	st := m.steps[m.at]
	if m.dry {
		what := st.detail
		if st.cmd != nil {
			what = strings.Join(st.cmd.Args, " ")
		}
		return func() tea.Msg { return stepDone{out: "would: " + what} }
	}
	if st.cmd != nil && st.interactive {
		// hand the terminal over (password prompts, download progress)
		c := exec.Command("sh", append([]string{"-c", `printf '\n\033[1m── strand: %s ──\033[0m\n' "$0"; exec "$@"`, st.title}, st.cmd.Args...)...)
		return tea.ExecProcess(c, func(err error) tea.Msg { return stepDone{err: err} })
	}
	if st.run != nil {
		return func() tea.Msg { out, err := st.run(); return stepDone{out: out, err: err} }
	}
	return func() tea.Msg { out, err := st.cmd.CombinedOutput(); return stepDone{out: string(out), err: err} }
}

func (m model) finishStep(d stepDone) (tea.Model, tea.Cmd) {
	st := &m.steps[m.at]
	st.note = lastLine(d.out)
	if d.err != nil {
		st.status = "fail"
		if st.note == "" || !strings.Contains(strings.ToLower(st.note), "error") {
			st.note = strings.TrimSpace(st.note + " " + d.err.Error())
		}
		m.failed = m.at
		return m, nil
	}
	st.status = "ok"
	m.at++
	if m.at >= len(m.steps) {
		m.screen = finished
		return m, nil
	}
	return m, m.runStep()
}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	l := strings.TrimSpace(lines[len(lines)-1])
	if len(l) > 110 {
		l = l[:109] + "…"
	}
	return l
}

// ── views ──

func (m model) View() string {
	if m.quitting {
		return ""
	}
	var body string
	switch m.screen {
	case welcome:
		body = m.viewWelcome()
	case pickParts:
		body = m.viewParts()
	case pickPearl:
		body = m.viewPearl()
	case enterKey:
		body = m.viewKey()
	case review:
		body = m.viewReview()
	case running, finished:
		body = m.viewRun()
	}
	w := 96
	if m.width > 0 && m.width-4 < w {
		w = m.width - 4
	}
	return "\n" + sFrame.Width(w).Render(body) + "\n"
}

func help(keys ...string) string {
	var parts []string
	for i := 0; i+1 < len(keys); i += 2 {
		parts = append(parts, sKey.Render(keys[i])+" "+sDim.Render(keys[i+1]))
	}
	return "\n" + strings.Join(parts, sDim.Render("  ·  "))
}

func check(ok bool, yes, no string) string {
	if ok {
		return sGood.Render("✓ ") + yes
	}
	return sBad.Render("✗ ") + no
}

func (m model) viewWelcome() string {
	s := m.sys
	var b strings.Builder
	b.WriteString(sTitle.Render(logo) + sDim.Render("   strand, the installer") + "\n\n")
	b.WriteString("An opinionated Quickshell shell for Hyprland: a bar, a Dynamic-Island-style\n")
	b.WriteString("launcher, a dashboard, lock screen and notifications, coloured by your wallpaper.\n\n")
	b.WriteString(check(s.arch, "Arch-based system (pacman)", "pacman not found: strand supports Arch-based systems only") + "\n")
	if s.arch {
		b.WriteString(check(s.helper != "", "AUR helper: "+s.helper, "no AUR helper (paru or yay): AUR packages will be listed for you to install") + "\n")
	}
	hypr := "Hyprland config: hyprland.conf"
	if s.hyprLua {
		hypr = "Hyprland config: hyprland.lua"
	}
	b.WriteString(sGood.Render("✓ ") + hypr + "\n")
	b.WriteString(sDim.Render("  installing from "+s.repo) + "\n")
	if m.dry {
		b.WriteString("\n" + sWarn.Render("dry run: nothing will be changed") + "\n")
	}
	if !s.arch {
		return b.String() + help("q", "quit")
	}
	return b.String() + help("enter", "choose parts", "q", "quit")
}

func (m model) viewParts() string {
	var b strings.Builder
	b.WriteString(sTitle.Render("What goes on the strand?") + "\n\n")
	c := m.chosen()
	for i, p := range m.parts {
		cur := "  "
		if i == m.cursor {
			cur = sAcc.Render("› ")
		}
		box := sDim.Render("○")
		if c.has(p.id) {
			box = sAcc.Render("●")
		}
		name := p.name
		if i == m.cursor {
			name = sTitle.Render(name)
		}
		tag := ""
		switch {
		case p.core:
			tag = sDim.Render("  always")
		case p.disable != "":
			tag = sWarn.Render("  " + p.disable)
		case p.needs != "" && !c.has(p.needs):
			tag = sDim.Render("  needs " + p.needs)
		}
		fmt.Fprintf(&b, "%s%s %s%s\n", cur, box, name, tag)
		fmt.Fprintf(&b, "     %s\n", sDim.Render(p.blurb))
	}
	return b.String() + help("space", "toggle", "enter", "next", "b", "back")
}

func (m model) viewPearl() string {
	var b strings.Builder
	b.WriteString(sTitle.Render("How should Pearl answer?") + "\n")
	b.WriteString(sDim.Render("Type ? in the launcher, or ask out loud with Murmur. You can change this later in Settings.") + "\n\n")
	for i, w := range pearlWays {
		cur, dot := "  ", sDim.Render("○")
		name := w.name
		if i == m.pearl {
			cur, dot, name = sAcc.Render("› "), sAcc.Render("●"), sTitle.Render(w.name)
		}
		fmt.Fprintf(&b, "%s%s %s\n     %s\n", cur, dot, name, sDim.Render(w.blurb))
	}
	if pearlWays[m.pearl].id == "claude" && !have("claude") {
		b.WriteString("\n" + sWarn.Render("The `claude` command isn't installed yet.") + "\n")
	}
	if pearlWays[m.pearl].id == "local" && !m.chosen().has("murmur") {
		b.WriteString("\n" + sWarn.Render("This turns Murmur on: it brings the local model.") + "\n")
	}
	return b.String() + help("↑↓", "choose", "enter", "next", "b", "back")
}

func (m model) viewKey() string {
	var b strings.Builder
	b.WriteString(sTitle.Render("Your Anthropic API key") + "\n")
	b.WriteString(sDim.Render("From console.anthropic.com. Saved to ~/.config/bead/anthropic-key, readable only by you.") + "\n")
	b.WriteString(sDim.Render("Leave it empty to add the file later.") + "\n\n")
	b.WriteString(m.key.View() + "\n")
	return b.String() + help("enter", "next", "esc", "back")
}

func (m model) viewReview() string {
	var b strings.Builder
	b.WriteString(sTitle.Render("Here's the plan") + "\n\n")
	if len(m.repoPkgs) > 0 {
		b.WriteString(sAcc.Render("Packages") + sDim.Render(" (sudo pacman asks for your password)") + "\n")
		b.WriteString(wrap(strings.Join(m.repoPkgs, " "), 76, "  ") + "\n\n")
	}
	if len(m.aurPkgs) > 0 {
		how := "via " + m.sys.helper
		if m.sys.helper == "" {
			how = "install these yourself: no AUR helper found"
		}
		b.WriteString(sAcc.Render("AUR") + sDim.Render(" ("+how+")") + "\n")
		b.WriteString(wrap(strings.Join(m.aurPkgs, " "), 76, "  ") + "\n\n")
	}
	if len(m.repoPkgs)+len(m.aurPkgs) == 0 {
		b.WriteString(sGood.Render("✓ ") + "every package is already installed\n\n")
	}
	if m.downloadMB > 0 {
		b.WriteString(sAcc.Render("Downloads") + "\n")
		for _, d := range murmurModels {
			fmt.Fprintf(&b, "  %s %s\n", d.name, sDim.Render(fmt.Sprintf("%d MB · huggingface.co", d.mb)))
		}
		b.WriteString(sDim.Render(fmt.Sprintf("  %d MB into %s", m.downloadMB, modelsDir)) + "\n\n")
	}
	b.WriteString(sAcc.Render("Steps") + "\n")
	for i, st := range m.steps {
		fmt.Fprintf(&b, "  %d. %s %s\n", i+1, st.title, sDim.Render("· "+trunc(st.detail, 58)))
	}
	b.WriteString("\n" + sDim.Render("Files strand edits are backed up first (*.bak-strand-<time>).") + "\n")
	if m.dry {
		b.WriteString(sWarn.Render("dry run: nothing will be changed") + "\n")
	}
	return b.String() + help("enter", "thread it", "b", "back", "q", "quit")
}

func (m model) viewRun() string {
	var b strings.Builder
	done := m.at
	if m.screen == finished {
		done = len(m.steps)
	}
	title := "Threading…"
	if m.screen == finished {
		title = "Done"
	}
	if m.failed >= 0 {
		title = "A step failed"
	}
	b.WriteString(sTitle.Render(title) + "   " + strandBar(done, len(m.steps), m.failed) + "\n\n")
	for i, st := range m.steps {
		var mark string
		switch {
		case st.status == "ok":
			mark = sGood.Render("✓")
		case st.status == "fail":
			mark = sBad.Render("✗")
		case st.status == "skip":
			mark = sWarn.Render("–")
		case i == m.at && m.screen == running:
			mark = m.spin.View()
		default:
			mark = sDim.Render("·")
		}
		fmt.Fprintf(&b, " %s %s\n", mark, st.title)
		if st.note != "" {
			style := sDim
			if st.status == "fail" {
				style = sBad
			}
			fmt.Fprintf(&b, "   %s\n", style.Render(st.note))
		}
	}
	if m.failed >= 0 {
		return b.String() + help("r", "retry", "s", "skip", "q", "quit")
	}
	if m.screen == finished {
		b.WriteString("\n" + m.nextSteps())
		return b.String() + help("enter", "close")
	}
	return b.String()
}

func (m model) nextSteps() string {
	c := m.chosen()
	var b strings.Builder
	b.WriteString(sAcc.Render("Next") + "\n")
	b.WriteString("  • Start it: " + sKey.Render("bead start") + sDim.Render(" (or log out and back in)") + "\n")
	b.WriteString("  • Wallpapers go in " + sKey.Render("~/Pictures/Wallpapers") + "\n")
	if c.has("binds") {
		b.WriteString("  • " + sKey.Render("Super") + " opens the launcher; " + sKey.Render("Super+K") + " the dashboard\n")
	}
	if c.has("glint") {
		b.WriteString("  • Try " + sKey.Render(`glint success "Hello"`) + "\n")
	}
	if c.has("huddle") {
		b.WriteString("  • Huddle: at discord.com/developers make an application, add the redirect\n")
		b.WriteString("    " + sKey.Render("http://localhost") + " under OAuth2, then paste its client id and secret into\n")
		b.WriteString("    " + sKey.Render("~/.config/bead/discord.json") + ". Discord asks you to allow it once.\n")
	}
	if c.has("phone") {
		b.WriteString("  • Phone link: install KDE Connect on your phone, then pair it in " + sKey.Render("Settings → Phone") + "\n")
	}
	if c.has("murmur") {
		b.WriteString("  • Murmur: hold " + sKey.Render("Super+Space") + " and speak; hold " + sKey.Render("Super+A") + " to dictate\n")
	}
	return b.String()
}

func wrap(s string, w int, indent string) string {
	var lines []string
	line := ""
	for _, word := range strings.Fields(s) {
		if len(line)+len(word)+1 > w && line != "" {
			lines = append(lines, indent+line)
			line = ""
		}
		if line != "" {
			line += " "
		}
		line += word
	}
	if line != "" {
		lines = append(lines, indent+line)
	}
	return strings.Join(lines, "\n")
}

func trunc(s string, n int) string {
	if len([]rune(s)) <= n {
		return s
	}
	return string([]rune(s)[:n-1]) + "…"
}
