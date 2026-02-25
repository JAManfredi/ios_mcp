class IosMcp < Formula
  desc "MCP server for headless iOS development — build, test, debug, and automate from the CLI"
  homepage "https://github.com/nicklama/ios-mcp"
  license "MIT"
  head "https://github.com/nicklama/ios-mcp.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/ios-mcp"
  end

  test do
    assert_match "ios-mcp", shell_output("#{bin}/ios-mcp --version")
  end
end
