package main

// The pieces strand can thread onto your system. Core is always installed;
// the rest are opt-in.

type part struct {
	id      string
	name    string
	blurb   string
	pkgs    []string // Arch packages (repo or AUR) it needs
	on      bool     // chosen by default
	core    bool
	needs   string // another part's id it depends on
	disable string // why it can't be chosen here ("" = it can)
}

func allParts() []*part {
	return []*part{
		{
			id: "core", name: "bead", core: true, on: true,
			blurb: "The shell: bar, island, launcher, dashboard, lock screen, notifications",
			pkgs: []string{
				"quickshell", "hyprland", "qt6-shadertools",
				"ttf-material-symbols-variable", "noto-fonts", "noto-fonts-emoji",
				"python", "jq", "curl", "fd", "libqalculate", "wtype", "wl-clipboard",
				"grim", "slurp", "ffmpeg", "wf-recorder", "hyprpicker", "cliphist",
				"libnotify", "pacman-contrib", "ddcutil", "pipewire", "make",
			},
		},
		{
			id: "tint", name: "Tint", on: true,
			blurb: "Colours drawn from your wallpaper (OKLCH palette, vibrant / muted / mono)",
			pkgs:  []string{"imagemagick"},
		},
		{
			id: "glint", name: "Glint", on: true,
			blurb: "Toasts from the terminal: `glint success \"Done\"`, confirm, choose, promise",
			pkgs:  []string{"go"},
		},
		{
			id: "glint-claude", name: "Glint for Claude Code", needs: "glint",
			blurb: "Allow / Deny, questions and \"finished\" toasts from Claude Code sessions",
		},
		{
			id: "murmur", name: "Murmur",
			blurb: "Voice commands and dictation, on your GPU, offline (~1.2 GB of models)",
			pkgs:  []string{"whisper-cpp", "llama-cpp"},
		},
		{
			id: "huddle", name: "Huddle",
			blurb: "Discord on the island: who's talking, mute / deafen, unread DMs",
		},
		{
			id: "pearl", name: "Pearl", on: true,
			blurb: "Ask a question from the launcher with \"?\" (Claude, or a local model)",
		},
		{
			id: "binds", name: "Hyprland keybinds", on: true,
			blurb: "Super for the launcher, Super+Tab overview, media keys, screenshots…",
		},
	}
}

// Murmur's models: whisper for speech, a small Qwen to turn it into an action.
type download struct {
	name, url, file string
	mb              int
}

var murmurModels = []download{
	{"whisper base.en", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin", "ggml-base.en.bin", 148},
	{"Qwen2.5 1.5B Instruct (Q4_K_M)", "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf", "qwen2.5-1.5b-instruct-q4_k_m.gguf", 1117},
}

// Pearl's ways to answer.
var pearlWays = []struct{ id, name, blurb string }{
	{"claude", "Claude Code", "uses your Claude Code login (the `claude` command)"},
	{"api", "Anthropic API key", "your own key, kept in ~/.config/bead/anthropic-key (chmod 600)"},
	{"local", "Local model", "offline, small and quick; needs Murmur's model"},
}
