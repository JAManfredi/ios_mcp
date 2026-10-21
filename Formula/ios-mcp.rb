class IosMcp < Formula
  desc "MCP server for headless iOS development — build, test, debug, and automate from the CLI"
  homepage "https://github.com/JAManfredi/ios_mcp"
  license "MIT"
  head "https://github.com/JAManfredi/ios_mcp.git", branch: "main"

  depends_on xcode: ["16.0", :build]  # tested through Xcode 27.1
  depends_on macos: :sonoma
  depends_on "cameroncooke/axe/axe"

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin_path = Utils.safe_popen_read("swift", "build", "-c", "release", "--show-bin-path").strip
    bin.install "#{bin_path}/ios-mcp"
  end

  test do
    assert_match "USAGE: ios-mcp", shell_output("#{bin}/ios-mcp --help")
  end
end
