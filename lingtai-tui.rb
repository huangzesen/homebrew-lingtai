class LingtaiTui < Formula
  desc "Terminal UI for the Lingtai AI agent framework"
  homepage "https://github.com/Lingtai-AI/lingtai"
  version "1.0.7"
  license "Apache-2.0"

  url "https://github.com/Lingtai-AI/lingtai/archive/refs/tags/v1.0.7.tar.gz"
  sha256 "b4a2a582274fa2504f35483485caf5d3ce78baaba5e8860aa4f53627f4430edc"

  depends_on "go" => :build
  depends_on "node" => :build
  depends_on "uv" => :recommended
  depends_on "python@3.13" => :recommended

  def install
    # Network mirror selection. Go-module mirrors and the npm registry are
    # configured independently — a Go proxy outage must not force an npm
    # registry switch (and vice versa).
    #
    # Go modules:
    #   1. HOMEBREW_GOPROXY (explicit user override) — community convention,
    #      survives Homebrew's superenv scrub because of the HOMEBREW_ prefix.
    #   2. Auto-detect: probe a stable proxy.golang.org API endpoint with a
    #      3s timeout. If unreachable (typical on mainland China networks),
    #      fall back to CN-accessible mirrors for Go modules and the Go
    #      checksum database (sum.golang.google.cn is Google's own
    #      CN-reachable alias of sum.golang.org, required for CN builds).
    #   3. Otherwise: leave ENV untouched — users elsewhere see no difference.
    #
    # npm registry:
    #   1. HOMEBREW_NPM_CONFIG_REGISTRY (explicit user override) — same
    #      HOMEBREW_ prefix trick so it survives the superenv scrub.
    #   2. Auto-detect ONLY when the Go proxy was unreachable AND an npm
    #      client probe to registry.npmmirror.com succeeds. Use npm (not curl)
    #      so the probe exercises the same Node/npm TLS trust store that
    #      `npm ci` will use; otherwise leave the npm registry on its default.
    #   3. Otherwise: leave ENV untouched.
    if ENV["HOMEBREW_GOPROXY"]
      ENV["GOPROXY"] = ENV["HOMEBREW_GOPROXY"]
      go_proxy_reachable = true
    else
      go_proxy_reachable = quiet_system(
        "curl", "-sSfL", "--max-time", "3", "-o", "/dev/null",
        "https://proxy.golang.org/github.com/golang/go/@latest"
      )
      unless go_proxy_reachable
        opoo "proxy.golang.org unreachable; using China-friendly Go build mirrors."
        ENV["GOPROXY"] = "https://goproxy.cn,direct"
        ENV["GOSUMDB"] = "sum.golang.google.cn"
      end
    end

    if ENV["HOMEBREW_NPM_CONFIG_REGISTRY"]
      ENV["NPM_CONFIG_REGISTRY"] = ENV["HOMEBREW_NPM_CONFIG_REGISTRY"]
    elsif !go_proxy_reachable
      npmmirror_reachable = quiet_system(
        "npm", "ping", "--registry=https://registry.npmmirror.com",
        "--fetch-timeout=3000", "--fetch-retries=0"
      )
      if npmmirror_reachable
        opoo "Using China-friendly npm registry (registry.npmmirror.com)."
        ENV["NPM_CONFIG_REGISTRY"] = "https://registry.npmmirror.com"
      else
        opoo "registry.npmmirror.com failed npm's connectivity/TLS probe; leaving npm registry unchanged. Set HOMEBREW_NPM_CONFIG_REGISTRY to override."
      end
    end

    cd "tui" do
      ldflags = "-X main.version=#{version}"
      system "go", "build", *std_go_args(ldflags: ldflags), "-o", bin/"lingtai-tui", "."
    end

    cd "portal" do
      cd "web" do
        system "npm", "ci"
        system "npm", "run", "build"
      end
      ldflags = "-X main.version=#{version}"
      system "go", "build", *std_go_args(ldflags: ldflags), "-o", bin/"lingtai-portal", "."
    end
  end

  test do
    assert_match "lingtai-tui", shell_output("#{bin}/lingtai-tui version 2>&1", 0)
  end
end
