#!/bin/bash

# Python user bin path (where pip installs user packages)
PYTHON_USER_BIN="$HOME/Library/Python/3.9/bin"

# Helper function to find speedtest-cli
find_speedtest_cli() {
    if command -v speedtest-cli >/dev/null 2>&1; then
        echo "speedtest-cli"
    elif [[ -x "$PYTHON_USER_BIN/speedtest-cli" ]]; then
        echo "$PYTHON_USER_BIN/speedtest-cli"
    else
        echo ""
    fi
}

# Check if this script is being called with "force-speedtest" argument
if [[ "$1" == "force-speedtest" ]]; then
    # Manual speed test mode
    cache_file="/tmp/.claude_speedtest_cache"
    lock_file="/tmp/.claude_speedtest_lock"
    
    echo "Running fresh speed test..."
    echo "This may take 30-60 seconds..."
    
    # Clear existing cache to force fresh test
    rm -f "$cache_file" 2>/dev/null
    
    # Remove any stale lock
    rm -f "$lock_file" 2>/dev/null
    
    # Check if speedtest-cli is available
    SPEEDTEST_CMD=$(find_speedtest_cli)
    if [[ -z "$SPEEDTEST_CMD" ]]; then
        echo "Error: speedtest-cli not found. Installing..."

        if command -v pip3 >/dev/null 2>&1; then
            echo "Installing via pip3..."
            pip3 install speedtest-cli
        elif command -v brew >/dev/null 2>&1; then
            echo "Installing via brew..."
            brew install speedtest-cli
        else
            echo "Error: Neither pip3 nor brew found. Please install speedtest-cli manually:"
            echo "  pip3 install speedtest-cli"
            echo "  # or"
            echo "  brew install speedtest-cli"
            exit 1
        fi

        # Check if installation was successful
        SPEEDTEST_CMD=$(find_speedtest_cli)
        if [[ -z "$SPEEDTEST_CMD" ]]; then
            echo "Error: Failed to install speedtest-cli"
            exit 1
        fi
    fi
    
    # Get current network for cache (reuse existing function)
    source_get_network_id() {
        local network_id=""
        
        # Try to get WiFi SSID using airport command
        local ssid=$((/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | grep " SSID" | awk '{print $2}') 2>/dev/null)
        
        # Fallback to networksetup if airport fails
        if [[ -z "$ssid" ]]; then
            ssid=$((networksetup -getairportnetwork en0 2>/dev/null | cut -d: -f2 | sed 's/^ *//') 2>/dev/null)
        fi
        
        if [[ -n "$ssid" && "$ssid" != "You are not associated with an AirPort network." ]]; then
            network_id="wifi:$ssid"
        else
            # For ethernet or other connections, use interface info
            local interface_info=$(route get default 2>/dev/null | grep interface | awk '{print $2}' 2>/dev/null)
            if [[ -n "$interface_info" ]]; then
                network_id="interface:$interface_info"
            else
                network_id="unknown"
            fi
        fi
        
        echo "$network_id"
    }
    
    current_network=$(source_get_network_id)
    current_time=$(date +%s)
    
    # Create lock file to prevent concurrent tests
    touch "$lock_file"
    
    # Run speed test with detailed output
    echo ""
    echo "Testing internet speed..."
    speedtest_result=$($SPEEDTEST_CMD --simple --timeout 60 2>&1)
    speedtest_exit_code=$?
    
    # Remove lock file
    rm -f "$lock_file"
    
    if [[ $speedtest_exit_code -eq 0 && -n "$speedtest_result" ]]; then
        echo ""
        echo "Speed test results:"
        echo "===================="
        echo "$speedtest_result"
        
        # Parse download and upload speeds for cache
        download=$(echo "$speedtest_result" | grep "Download:" | awk '{print $2}' | sed 's/[^0-9.]//g')
        upload=$(echo "$speedtest_result" | grep "Upload:" | awk '{print $2}' | sed 's/[^0-9.]//g')
        
        if [[ -n "$download" && -n "$upload" ]]; then
            # Format speeds as integers for status line
            down_int=$(printf "%.0f" "$download" 2>/dev/null || echo "0")
            up_int=$(printf "%.0f" "$upload" 2>/dev/null || echo "0")
            
            speed_display="↓ ${down_int}Mbps ↑ ${up_int}Mbps"
            
            # Cache the result
            {
                echo "$current_time"
                echo "$current_network"
                echo "$speed_display"
            } > "$cache_file"
            
            echo ""
            echo "Results cached for status line display."
            echo "Status line will show: $speed_display"
        fi
    else
        echo ""
        echo "Error: Speed test failed"
        if [[ -n "$speedtest_result" ]]; then
            echo "Error details: $speedtest_result"
        fi
        exit 1
    fi
    
    exit 0
fi

# Check if this script is being called with "speed-check" argument for natural language detection
if [[ "$1" == "speed-check" ]]; then
    # Get input either from second argument or stdin
    user_input=""
    if [[ $# -gt 1 ]]; then
        shift  # Remove first argument
        user_input="$*"
    elif [[ ! -t 0 ]]; then
        user_input=$(cat)
    fi
    
    # If no input, just run the speed test
    if [[ -z "$user_input" ]]; then
        bash ~/.claude/statusline.sh force-speedtest
        exit 0
    fi
    
    # Convert to lowercase for pattern matching
    user_input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')
    
    # Keywords that trigger a speed test
    speed_test_patterns=(
        "run speed test"
        "speed test"
        "check speed"
        "test internet speed"
        "internet speed test"
        "test my speed"
        "check internet speed"
        "run speedtest"
        "speedtest please"
        "test speed"
        "speed check"
        "check my speed"
        "what's my speed"
        "how fast is my internet"
    )
    
    # Check if any pattern matches
    for pattern in "${speed_test_patterns[@]}"; do
        if [[ "$user_input_lower" == *"$pattern"* ]]; then
            echo "Detected speed test request: '$user_input'"
            bash ~/.claude/statusline.sh force-speedtest
            exit 0
        fi
    done
    
    # No speed test pattern found
    echo "No speed test pattern detected in: '$user_input'"
    echo "Try phrases like 'run speed test', 'check my speed', or 'test internet speed'"
    exit 1
fi

# Read JSON input from stdin for normal status line mode
input=$(cat)

# Extract data from JSON input
model_id=$(echo "$input" | jq -r '.model.id')
version=$(echo "$input" | jq -r '.version')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
context_used_percentage=$(echo "$input" | jq -r '.context_window.used_percentage')
rate_limit_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# Get git branch name (skip locks to avoid delays)
cd "$current_dir" 2>/dev/null
git_branch=$(git branch --show-current 2>/dev/null)

# If no branch found in current_dir, try project_dir
if [[ -z "$git_branch" ]]; then
    project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
    if [[ -n "$project_dir" ]]; then
        cd "$project_dir" 2>/dev/null
        git_branch=$(git branch --show-current 2>/dev/null)
    fi
fi

# Default to "no-git" if still no branch found
[[ -z "$git_branch" ]] && git_branch="no-git"

# Get current network identifier for cache invalidation
get_network_id() {
    local network_id=""
    
    # Try to get WiFi SSID using airport command
    local ssid=$((/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | grep " SSID" | awk '{print $2}') 2>/dev/null)
    
    # Fallback to networksetup if airport fails
    if [[ -z "$ssid" ]]; then
        ssid=$((networksetup -getairportnetwork en0 2>/dev/null | cut -d: -f2 | sed 's/^ *//') 2>/dev/null)
    fi
    
    if [[ -n "$ssid" && "$ssid" != "You are not associated with an AirPort network." ]]; then
        network_id="wifi:$ssid"
    else
        # For ethernet or other connections, use interface info
        local interface_info=$(route get default 2>/dev/null | grep interface | awk '{print $2}' 2>/dev/null)
        if [[ -n "$interface_info" ]]; then
            network_id="interface:$interface_info"
        else
            network_id="unknown"
        fi
    fi
    
    echo "$network_id"
}

# Get actual internet speed using speedtest with caching
get_speed_test() {
    local cache_file="/tmp/.claude_speedtest_cache"
    local lock_file="/tmp/.claude_speedtest_lock"
    local cache_max_age=3600  # 60 minutes in seconds
    local current_time=$(date +%s)
    local current_network=$(get_network_id)
    local use_cache=false
    
    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
        local cached_network=$(sed -n '2p' "$cache_file" 2>/dev/null)
        
        if [[ -n "$cache_timestamp" && "$cache_timestamp" =~ ^[0-9]+$ ]]; then
            local cache_age=$((current_time - cache_timestamp))
            
            # Use cache only if it's fresh AND network hasn't changed
            if [[ $cache_age -lt $cache_max_age && "$cached_network" == "$current_network" ]]; then
                use_cache=true
            fi
        fi
    fi
    
    # Use cached data if fresh
    if [[ "$use_cache" == true ]]; then
        # Read cached speed data (skip timestamp and network lines)
        local cached_result=$(tail -n +3 "$cache_file" 2>/dev/null)
        if [[ -n "$cached_result" ]]; then
            printf " | %s" "$cached_result"
            return
        fi
    fi
    
    # Check if speedtest is running to avoid multiple concurrent tests
    if [[ -f "$lock_file" ]]; then
        local lock_age=$((current_time - $(stat -f %m "$lock_file" 2>/dev/null || echo "0")))
        if [[ $lock_age -lt 120 ]]; then  # Lock timeout after 2 minutes
            # Show cached result or placeholder if test is running
            local cached_result=$(tail -n +3 "$cache_file" 2>/dev/null)
            if [[ -n "$cached_result" ]]; then
                printf " | %s (testing...)" "$cached_result"
            else
                printf " | ↓ --Mbps ↑ --Mbps (testing...)"
            fi
            return
        else
            # Remove stale lock
            rm -f "$lock_file" 2>/dev/null
        fi
    fi
    
    # Check if speedtest-cli is available
    local speedtest_cmd=$(find_speedtest_cli)
    if [[ -z "$speedtest_cmd" ]]; then
        # Try to install speedtest-cli using pip3 or brew
        if command -v pip3 >/dev/null 2>&1; then
            # Run installation in background to not block status line
            (
                touch "$lock_file"
                pip3 install speedtest-cli >/dev/null 2>&1
                rm -f "$lock_file"
            ) &
        elif command -v brew >/dev/null 2>&1; then
            # Run installation in background to not block status line
            (
                touch "$lock_file"
                brew install speedtest-cli >/dev/null 2>&1
                rm -f "$lock_file"
            ) &
        fi
        printf " | ↓ --Mbps ↑ --Mbps (installing...)"
        return
    fi
    
    # Run speed test in background if cache is stale
    if [[ "$use_cache" != true ]]; then
        # Start background speed test
        (
            # Create lock file
            touch "$lock_file"
            
            # Run speed test and parse results
            local speedtest_result
            speedtest_result=$($speedtest_cmd --simple --timeout 60 2>/dev/null)
            
            if [[ $? -eq 0 && -n "$speedtest_result" ]]; then
                # Parse download and upload speeds
                local download upload
                download=$(echo "$speedtest_result" | grep "Download:" | awk '{print $2}' | sed 's/[^0-9.]//g')
                upload=$(echo "$speedtest_result" | grep "Upload:" | awk '{print $2}' | sed 's/[^0-9.]//g')
                
                if [[ -n "$download" && -n "$upload" ]]; then
                    # Format speeds as integers for cleaner display
                    local down_int up_int
                    down_int=$(printf "%.0f" "$download" 2>/dev/null || echo "0")
                    up_int=$(printf "%.0f" "$upload" 2>/dev/null || echo "0")
                    
                    local speed_display="↓ ${down_int}Mbps ↑ ${up_int}Mbps"
                    
                    # Cache the result with network identifier
                    {
                        echo "$current_time"
                        echo "$current_network"
                        echo "$speed_display"
                    } > "$cache_file"
                fi
            fi
            
            # Remove lock file
            rm -f "$lock_file"
        ) &
    fi
    
    # Show cached result or placeholder while test runs
    local cached_result=$(tail -n +3 "$cache_file" 2>/dev/null)
    if [[ -n "$cached_result" ]]; then
        printf " | %s" "$cached_result"
    else
        printf " | ↓ --Mbps ↑ --Mbps"
    fi
}

# Get context usage progress bar
get_context_progress_bar() {
    local used_percentage="$1"
    local bar_char="█"
    local empty_char="░"
    local bar=""
    local color_start=""
    local color_end="\033[0m"

    # Handle missing or invalid percentage
    if [[ -z "$used_percentage" || "$used_percentage" == "null" ]]; then
        return
    fi

    # Round to integer for display and calculations
    local percent_int=$(printf "%.0f" "$used_percentage" 2>/dev/null || echo "0")

    # Set bar width and format based on threshold
    local bar_width
    local show_percentage=false
    if [[ $percent_int -ge 64 ]]; then
        bar_width=16
        show_percentage=true
        color_start="\033[31m"  # Red
    else
        bar_width=20
    fi

    # Calculate filled width
    local filled_width=$((percent_int * bar_width / 100))
    local empty_width=$((bar_width - filled_width))

    # Build the progress bar
    for ((i=0; i<filled_width; i++)); do
        bar+="$bar_char"
    done
    for ((i=0; i<empty_width; i++)); do
        bar+="$empty_char"
    done

    if [[ "$show_percentage" == true ]]; then
        printf "\nContext [%s] %d%%%b" "$bar" "$percent_int" "$color_end"
    else
        printf "\nContext [%s] %d%%" "$bar" "$percent_int"
    fi
}

# Get weather information with caching using Open-Meteo API
get_weather() {
    local cache_file="/tmp/.claude_weather_cache"
    local cache_max_age=1200  # 20 minutes in seconds
    local current_time=$(date +%s)
    local weather_json current_temp high_temp low_temp weather_code weather_text
    local use_cache=false
    
    # CUSTOMIZE: Set your location coordinates and timezone
    # Default: San Francisco (Anthropic HQ) - Update these for your location
    # Find coordinates at: https://www.latlong.net/
    local latitude="41.4993"
    local longitude="-81.6944"
    local timezone="America/New_York"
    
    # Create location identifier for cache invalidation
    local location_id="${latitude},${longitude}"

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
        local cached_location=$(sed -n '2p' "$cache_file" 2>/dev/null)
        if [[ -n "$cache_timestamp" && "$cache_timestamp" =~ ^[0-9]+$ ]]; then
            local cache_age=$((current_time - cache_timestamp))
            # Use cache only if fresh AND location hasn't changed
            if [[ $cache_age -lt $cache_max_age && "$cached_location" == "$location_id" ]]; then
                use_cache=true
            fi
        fi
    fi
    
    # Use cached data if fresh, otherwise fetch new data
    if [[ "$use_cache" == true ]]; then
        # Read cached weather data (skip timestamp and location lines)
        weather_json=$(tail -n +3 "$cache_file" 2>/dev/null)
    else
        # Fetch fresh weather data from Open-Meteo API
        # Get current conditions plus daily high/low
        local api_url="https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=${timezone}&forecast_days=1"
        weather_json=$(curl -s -m 3 "$api_url" 2>/dev/null)
        
        # Cache the data if we got a valid response
        if [[ -n "$weather_json" && "$weather_json" != *"error"* ]]; then
            # Store timestamp, location, and weather data in cache file
            {
                echo "$current_time"
                echo "$location_id"
                echo "$weather_json"
            } > "$cache_file"
        fi
    fi
    
    # Process weather data (whether from cache or fresh fetch)
    if [[ -n "$weather_json" && "$weather_json" != *"error"* ]]; then
        # Extract data using jq
        current_temp=$(echo "$weather_json" | jq -r '.current.temperature_2m' 2>/dev/null)
        weather_code=$(echo "$weather_json" | jq -r '.current.weather_code' 2>/dev/null)
        high_temp=$(echo "$weather_json" | jq -r '.daily.temperature_2m_max[0]' 2>/dev/null)
        low_temp=$(echo "$weather_json" | jq -r '.daily.temperature_2m_min[0]' 2>/dev/null)
        
        # Check if we got valid data
        if [[ -n "$current_temp" && -n "$weather_code" && -n "$high_temp" && -n "$low_temp" && \
              "$current_temp" != "null" && "$weather_code" != "null" && "$high_temp" != "null" && "$low_temp" != "null" ]]; then
            
            # Map weather codes to text descriptions
            case "$weather_code" in
                0) weather_text="sunny" ;;
                1|2) weather_text="partly-cloudy" ;;
                3) weather_text="cloudy" ;;
                45|48) weather_text="fog" ;;
            
                # drizzle (includes freezing drizzle 56/57)
                51|53|55|56|57) weather_text="drizzle" ;;
            
                # freezing rain (not drizzle)
                66|67) weather_text="freezing-rain" ;;
            
                # rain (non-freezing)
                61|63|65|80|81|82) weather_text="rain" ;;
            
                # keep other groups
                71|73|75|77|85|86) weather_text="snow" ;;
                95|96|99) weather_text="thunderstorm" ;;
                *) weather_text="fair" ;;
            esac
            
            # Round temperatures to integers for display
            current_temp_int=$(printf "%.0f" "$current_temp" 2>/dev/null || echo "$current_temp")
            high_temp_int=$(printf "%.0f" "$high_temp" 2>/dev/null || echo "$high_temp")
            low_temp_int=$(printf "%.0f" "$low_temp" 2>/dev/null || echo "$low_temp")
            
            # Format: [condition] [temp]°F ([high]°F/[low]°F)
            printf " | %s %s°F (%s°F/%s°F)" "$weather_text" "$current_temp_int" "$high_temp_int" "$low_temp_int"
        else
            # Fallback if JSON parsing fails
            printf " | weather --"
        fi
    else
        # Fallback if weather service is unavailable
        printf " | weather --"
    fi
}


# Format and output the status line
printf "⎇ %s | %s | v%s%s%s" \
    "$git_branch" \
    "$model_id" \
    "$version" \
    "$(get_speed_test)" \
    "$(get_weather)"

# Display context usage progress bar
get_context_progress_bar "$context_used_percentage"

# Display rate limit usage bar (5-hour session usage)
get_rate_limit_bar() {
    local used_percentage="$1"
    local bar_char="█"
    local empty_char="░"
    local bar=""

    # Skip if no rate limit data available
    if [[ -z "$used_percentage" || "$used_percentage" == "null" ]]; then
        return
    fi

    local percent_int=$(printf "%.0f" "$used_percentage" 2>/dev/null || echo "0")

    local bar_width=20
    local color_start=""
    local color_end="\033[0m"

    # Color based on usage: cyan < 50%, yellow 50-79%, magenta >= 80%
    if [[ $percent_int -ge 80 ]]; then
        color_start="\033[35m"  # Magenta
    elif [[ $percent_int -ge 50 ]]; then
        color_start="\033[33m"  # Yellow
    else
        color_start="\033[36m"  # Cyan
    fi

    local filled_width=$((percent_int * bar_width / 100))
    local empty_width=$((bar_width - filled_width))

    for ((i=0; i<filled_width; i++)); do
        bar+="$bar_char"
    done
    for ((i=0; i<empty_width; i++)); do
        bar+="$empty_char"
    done

    printf "\n%bSession [%s] %d%%%b" "$color_start" "$bar" "$percent_int" "$color_end"
}

get_rate_limit_bar "$rate_limit_pct"
