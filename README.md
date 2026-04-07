# Claude Code Statusline

A custom statusline script for [Claude Code](https://claude.ai/code) that displays useful information at a glance.

## Features

- **Git branch** — current branch name
- **Model ID** — active Claude model
- **Version** — Claude Code version
- **Internet speed** — download/upload speeds (cached, updates hourly or on network change)
- **Weather** — current conditions and temperature with daily high/low
- **Context usage** — progress bar showing context window usage (turns red at 64%)
- **Session usage** — 5-hour rate limit usage bar with color coding (cyan → yellow → magenta)

## Screenshot

```
⎇ main | claude-opus-4-6 | v1.0.50 | ↓ 150Mbps ↑ 12Mbps | sunny 72°F (78°F/65°F)
[████████████░░░░░░░░]
Session [████████░░░░░░░░░░░░] 40%
```

## Installation

1. Copy `statusline.sh` to `~/.claude/`:
   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Merge the settings from `settings.json` into your `~/.claude/settings.json`. The key settings are:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     },
     "commands": {
       "speedtest": {
         "command": "bash ~/.claude/statusline.sh force-speedtest",
         "description": "Run a fresh internet speed test"
       }
     }
   }
   ```

   The included `settings.json` also contains recommended `permissions`, `includeCoAuthoredBy`, and `enabledPlugins` settings that you can optionally adopt.

3. Install dependencies:
   ```bash
   # jq (required for JSON parsing)
   brew install jq

   # speedtest-cli (optional, will auto-install if missing)
   pip3 install speedtest-cli
   # or
   brew install speedtest-cli
   ```

## Configuration

### Weather Location (Required)

The script defaults to San Francisco (Anthropic HQ). **Update this to your location** in `statusline.sh`:

```bash
# Find this section in get_weather() function (~line 413)
# CUSTOMIZE: Set your location coordinates and timezone
local latitude="37.790024"    # Your latitude
local longitude="-122.400833" # Your longitude
local timezone="America/Los_Angeles"  # Your timezone
```

**How to find your coordinates:**
- Visit [latlong.net](https://www.latlong.net/)
- Enter your city or zip code
- Copy the latitude and longitude values

**Common timezones:**
- `America/New_York` — Eastern
- `America/Chicago` — Central
- `America/Denver` — Mountain
- `America/Los_Angeles` — Pacific

### GitHub Token (Optional)

For higher GitHub API rate limits (5000/hour vs 60/hour), create a token file:

```bash
mkdir -p ~/.config/github
echo "your_github_token" > ~/.config/github/token
chmod 600 ~/.config/github/token
```

## Commands

### Manual Speed Test

Run a fresh speed test (bypasses cache):

```
/speedtest
```

Or from terminal:
```bash
~/.claude/statusline.sh force-speedtest
```

## Caching

| Feature | Cache Duration | Invalidation |
|---------|----------------|--------------|
| Speed test | 60 minutes | Network change (WiFi SSID or interface) |
| Weather | 20 minutes | Time-based |

## Context Progress Bar

The progress bar shows context window usage:
- **Below 64%** — simple bar, no percentage shown
- **64% and above** — bar turns red, percentage displayed

This gives you warning before Claude Code's auto-compact triggers (~95%).

## Session Usage Bar

Shows your 5-hour rate limit usage as a progress bar:
- **Below 50%** — cyan
- **50-79%** — yellow
- **80%+** — magenta

This data comes from Claude Code's built-in `rate_limits.five_hour.used_percentage` field, available to any status line script.

## Dependencies

- **bash** — shell interpreter
- **jq** — JSON parsing (required)
- **curl** — API requests (usually pre-installed)
- **speedtest-cli** — internet speed testing (optional, auto-installs)

## macOS Specific

This script uses macOS-specific commands for:
- WiFi SSID detection (`airport`, `networksetup`)
- File timestamps (`stat -f`)

Modifications may be needed for Linux compatibility.

## License

This project is released under the MIT License. See the [LICENSE](LICENSE) file for more information.
