#!/bin/bash
#
# User Login Report Script for Amazon Linux 2023
# Analyzes /var/log/audit/ logs for user login statistics
#
# Usage:
#   ./user_login_report.sh          # Current year report (today, week, month, year)
#   ./user_login_report.sh 2024     # Month-wise report for specific year
#
# Author: Generated for Harness
# Requires: root/sudo access to read audit logs
#

set -euo pipefail

# Configuration
AUDIT_LOG_DIR="/var/log/audit"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_prerequisites() {
    # Check if audit log directory exists
    if [[ ! -d "$AUDIT_LOG_DIR" ]]; then
        log_error "Audit log directory '$AUDIT_LOG_DIR' does not exist."
        log_error "Ensure auditd is installed and running: sudo systemctl status auditd"
        exit 1
    fi

    # Check if we can read audit logs
    if [[ ! -r "$AUDIT_LOG_DIR/audit.log" ]]; then
        log_error "Cannot read audit logs. Please run with sudo or as root."
        exit 1
    fi

    # Check for required commands
    local required_cmds=("awk" "grep" "sort" "uniq" "date")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found."
            exit 1
        fi
    done
}

validate_year() {
    local year="$1"

    # Check if it's a valid 4-digit year
    if ! [[ "$year" =~ ^[0-9]{4}$ ]]; then
        log_error "Invalid year format: '$year'. Please provide a 4-digit year (e.g., 2024)."
        exit 1
    fi

    # Check reasonable year range (2000-2099)
    if [[ "$year" -lt 2000 ]] || [[ "$year" -gt 2099 ]]; then
        log_error "Year must be between 2000 and 2099."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Audit Log Parsing Functions
# -----------------------------------------------------------------------------

# Check if an audit log file contains events for the target year
# Returns 0 if file has relevant data, 1 otherwise
file_has_year_data() {
    local file="$1"
    local year_start_epoch="$2"
    local year_end_epoch="$3"

    # Get first and last epoch from the file using portable sed/awk
    local first_epoch last_epoch

    # Get first timestamp in file (portable approach)
    first_epoch=$(head -100 "$file" 2>/dev/null | \
        sed -n 's/.*msg=audit(\([0-9]*\).*/\1/p' | head -1)

    # Get last timestamp in file
    last_epoch=$(tail -100 "$file" 2>/dev/null | \
        sed -n 's/.*msg=audit(\([0-9]*\).*/\1/p' | tail -1)

    # If we can't determine timestamps, include the file to be safe
    if [[ -z "$first_epoch" ]] || [[ -z "$last_epoch" ]]; then
        return 0
    fi

    # Check if file's time range overlaps with target year
    # File overlaps if: file_start <= year_end AND file_end >= year_start
    if [[ "$first_epoch" -le "$year_end_epoch" ]] && [[ "$last_epoch" -ge "$year_start_epoch" ]]; then
        return 0
    fi

    return 1
}

# Extract login events from audit logs for a specific year
# Output: EPOCH_TIMESTAMP|USERNAME|DATE_YYYY-MM-DD
extract_login_events() {
    local output_file="$1"
    local target_year="$2"

    log_info "Extracting login events for year $target_year from audit logs..."

    # Calculate epoch range for target year
    local year_start_epoch year_end_epoch
    year_start_epoch=$(date -d "$target_year-01-01 00:00:00" '+%s' 2>/dev/null)
    year_end_epoch=$(date -d "$target_year-12-31 23:59:59" '+%s' 2>/dev/null)

    if [[ -z "$year_start_epoch" ]] || [[ -z "$year_end_epoch" ]]; then
        log_error "Failed to calculate epoch range for year $target_year"
        touch "$output_file"
        return
    fi

    log_info "Target year epoch range: $year_start_epoch - $year_end_epoch"

    # Collect audit log files that contain data for target year
    local audit_files=()
    local skipped_files=0

    # Check main audit.log
    if [[ -f "$AUDIT_LOG_DIR/audit.log" ]]; then
        if file_has_year_data "$AUDIT_LOG_DIR/audit.log" "$year_start_epoch" "$year_end_epoch"; then
            audit_files+=("$AUDIT_LOG_DIR/audit.log")
        else
            ((skipped_files++))
        fi
    fi

    # Check rotated logs (audit.log.1, audit.log.2, etc.)
    for rotated in "$AUDIT_LOG_DIR"/audit.log.[0-9]*; do
        if [[ -f "$rotated" ]]; then
            if file_has_year_data "$rotated" "$year_start_epoch" "$year_end_epoch"; then
                audit_files+=("$rotated")
            else
                ((skipped_files++))
            fi
        fi
    done

    # Check compressed rotated logs
    for compressed in "$AUDIT_LOG_DIR"/audit.log.*.gz; do
        if [[ -f "$compressed" ]]; then
            # Decompress to temp file
            local temp_file="$TEMP_DIR/$(basename "$compressed" .gz)"
            zcat "$compressed" > "$temp_file" 2>/dev/null || continue

            if [[ -s "$temp_file" ]]; then
                if file_has_year_data "$temp_file" "$year_start_epoch" "$year_end_epoch"; then
                    audit_files+=("$temp_file")
                else
                    rm -f "$temp_file"
                    ((skipped_files++))
                fi
            fi
        fi
    done

    if [[ ${#audit_files[@]} -eq 0 ]]; then
        log_warn "No audit log files found containing data for year $target_year"
        [[ $skipped_files -gt 0 ]] && log_info "Skipped $skipped_files file(s) outside target year range"
        touch "$output_file"
        return
    fi

    log_info "Processing ${#audit_files[@]} audit log file(s) for year $target_year"
    [[ $skipped_files -gt 0 ]] && log_info "Skipped $skipped_files file(s) outside target year range"

    # Parse audit logs for successful USER_LOGIN events within target year
    cat "${audit_files[@]}" 2>/dev/null | \
    grep -E 'type=(USER_LOGIN|USER_START)' | \
    grep -i 'res=success' | \
    awk -v year_start="$year_start_epoch" -v year_end="$year_end_epoch" '
    {
        line = $0
        epoch = ""
        username = ""

        # Extract timestamp from msg=audit(EPOCH.xxx:xxx) or msg=audit(EPOCH:xxx)
        if (match(line, /msg=audit\([0-9]+/)) {
            temp = substr(line, RSTART + 10)
            split(temp, ts_parts, /[.:]/)
            epoch = ts_parts[1]
        }

        if (epoch == "") next

        # Filter by target year epoch range
        if (epoch < year_start || epoch > year_end) next

        # Extract username from acct="username"
        if (match(line, /acct="[^"]+"/)) {
            temp = substr(line, RSTART + 6, RLENGTH - 7)
            username = temp
        } else if (match(line, /acct=[^ ]+/)) {
            temp = substr(line, RSTART + 5, RLENGTH - 5)
            gsub(/"/, "", temp)
            username = temp
        }

        # Skip if no valid username or system accounts
        if (username == "" || username == "?" || username == "(unknown)") {
            next
        }

        # Skip system accounts with UID < 1000 naming patterns
        if (username ~ /^(nobody|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|systemd|syslog|messagebus|_apt|uuidd|tcpdump|sshd|landscape|pollinate|ec2-instance-connect|ssm-user)$/) {
            next
        }

        print epoch "|" username
    }
    ' | sort -u > "$TEMP_DIR/raw_events.txt"

    # Convert epoch to date format
    while IFS='|' read -r epoch username; do
        if [[ -n "$epoch" ]] && [[ -n "$username" ]]; then
            login_date=$(date -d "@$epoch" '+%Y-%m-%d' 2>/dev/null) || continue
            echo "$epoch|$username|$login_date"
        fi
    done < "$TEMP_DIR/raw_events.txt" > "$output_file"

    local event_count
    event_count=$(wc -l < "$output_file" | tr -d ' ')
    log_info "Found $event_count login events for year $target_year"
}

# -----------------------------------------------------------------------------
# Report Generation Functions
# -----------------------------------------------------------------------------

generate_current_year_report() {
    local events_file="$1"

    local current_year
    current_year=$(date '+%Y')

    local today
    today=$(date '+%Y-%m-%d')

    # Calculate week start (Monday of current week)
    # Compatible with GNU date on Amazon Linux 2023
    local week_start
    local day_of_week
    day_of_week=$(date '+%u')  # 1=Monday, 7=Sunday

    if [[ "$day_of_week" -eq 1 ]]; then
        # Today is Monday
        week_start="$today"
    else
        # Calculate days since Monday
        local days_since_monday=$((day_of_week - 1))
        week_start=$(date -d "$today - $days_since_monday days" '+%Y-%m-%d' 2>/dev/null)
        if [[ -z "$week_start" ]]; then
            # Fallback for older date versions
            week_start=$(date -d "-$days_since_monday days" '+%Y-%m-%d' 2>/dev/null || echo "$today")
        fi
    fi

    # Calculate month start
    local month_start
    month_start=$(date '+%Y-%m-01')

    # Calculate year start
    local year_start
    year_start="$current_year-01-01"

    log_info "Generating current year ($current_year) report..."
    log_info "  Today: $today"
    log_info "  Week start: $week_start"
    log_info "  Month start: $month_start"

    # Get unique users from events file
    local users_file="$TEMP_DIR/users.txt"
    awk -F'|' '{print $2}' "$events_file" | sort -u > "$users_file"

    if [[ ! -s "$users_file" ]]; then
        log_warn "No login events found for the current year."
        echo ""
        echo "No login data available."
        return
    fi

    # Calculate stats for each user
    echo ""
    printf "${BOLD}%-20s %12s %15s %15s %15s${NC}\n" \
        "USERNAME" "TODAY" "THIS_WEEK" "THIS_MONTH" "THIS_YEAR"
    printf "%-20s %12s %15s %15s %15s\n" \
        "--------------------" "------------" "---------------" "---------------" "---------------"

    while read -r username; do
        [[ -z "$username" ]] && continue

        # Count logins for each period
        local today_count=0
        local week_count=0
        local month_count=0
        local year_count=0

        while IFS='|' read -r epoch user login_date; do
            [[ "$user" != "$username" ]] && continue

            # This year (all events are already filtered for current year)
            ((year_count++))

            # This month
            if [[ "$login_date" > "$month_start" || "$login_date" == "$month_start" ]]; then
                ((month_count++))
            fi

            # This week
            if [[ "$login_date" > "$week_start" || "$login_date" == "$week_start" ]]; then
                ((week_count++))
            fi

            # Today
            if [[ "$login_date" == "$today" ]]; then
                ((today_count++))
            fi
        done < "$events_file"

        # Only print users with at least one login
        if [[ $year_count -gt 0 ]]; then
            printf "%-20s %12d %15d %15d %15d\n" \
                "$username" "$today_count" "$week_count" "$month_count" "$year_count"
        fi
    done < "$users_file" | sort -t' ' -k5 -nr

    # Calculate and print totals
    local total_today=0 total_week=0 total_month=0 total_year=0

    while IFS='|' read -r epoch user login_date; do
        [[ -z "$login_date" ]] && continue

        # All events are already filtered for current year
        ((total_year++))
        [[ "$login_date" > "$month_start" || "$login_date" == "$month_start" ]] && ((total_month++))
        [[ "$login_date" > "$week_start" || "$login_date" == "$week_start" ]] && ((total_week++))
        [[ "$login_date" == "$today" ]] && ((total_today++))
    done < "$events_file"

    printf "%-20s %12s %15s %15s %15s\n" \
        "--------------------" "------------" "---------------" "---------------" "---------------"
    printf "${BOLD}%-20s %12d %15d %15d %15d${NC}\n" \
        "TOTAL" "$total_today" "$total_week" "$total_month" "$total_year"

    echo ""
}

generate_year_report() {
    local events_file="$1"
    local target_year="$2"

    log_info "Generating month-wise report for year $target_year..."

    # Count events by user and month (data already filtered for target year)
    local monthly_stats="$TEMP_DIR/monthly_stats.txt"

    awk -F'|' '
    {
        login_date = $3
        username = $2

        # Extract month from date
        split(login_date, date_parts, "-")
        login_month = date_parts[2]

        key = username "|" login_month
        count[key]++
        users[username] = 1
    }
    END {
        for (user in users) {
            printf "%s", user
            total = 0
            for (m = 1; m <= 12; m++) {
                month = sprintf("%02d", m)
                key = user "|" month
                c = (key in count) ? count[key] : 0
                printf "|%d", c
                total += c
            }
            printf "|%d\n", total
        }
    }
    ' "$events_file" | sort -t'|' -k14 -nr > "$monthly_stats"

    if [[ ! -s "$monthly_stats" ]]; then
        log_warn "No login events found for year $target_year."
        echo ""
        echo "No login data available for $target_year."
        return
    fi

    # Print header
    echo ""
    printf "${BOLD}%-15s" "USERNAME"
    for month in JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC; do
        printf " %5s" "$month"
    done
    printf " %7s${NC}\n" "TOTAL"

    # Print separator
    printf "%-15s" "---------------"
    for _ in {1..12}; do
        printf " %5s" "-----"
    done
    printf " %7s\n" "-------"

    # Print data and calculate totals
    local t1=0 t2=0 t3=0 t4=0 t5=0 t6=0 t7=0 t8=0 t9=0 t10=0 t11=0 t12=0 grand_total=0

    while IFS='|' read -r username m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 total; do
        [[ -z "$username" ]] && continue
        printf "%-15s %5d %5d %5d %5d %5d %5d %5d %5d %5d %5d %5d %5d %7d\n" \
            "$username" "$m1" "$m2" "$m3" "$m4" "$m5" "$m6" "$m7" "$m8" "$m9" "$m10" "$m11" "$m12" "$total"

        ((t1 += m1)) || true
        ((t2 += m2)) || true
        ((t3 += m3)) || true
        ((t4 += m4)) || true
        ((t5 += m5)) || true
        ((t6 += m6)) || true
        ((t7 += m7)) || true
        ((t8 += m8)) || true
        ((t9 += m9)) || true
        ((t10 += m10)) || true
        ((t11 += m11)) || true
        ((t12 += m12)) || true
        ((grand_total += total)) || true
    done < "$monthly_stats"

    # Print totals row
    printf "%-15s" "---------------"
    for _ in {1..12}; do
        printf " %5s" "-----"
    done
    printf " %7s\n" "-------"

    printf "${BOLD}%-15s %5d %5d %5d %5d %5d %5d %5d %5d %5d %5d %5d %5d %7d${NC}\n" \
        "TOTAL" "$t1" "$t2" "$t3" "$t4" "$t5" "$t6" "$t7" "$t8" "$t9" "$t10" "$t11" "$t12" "$grand_total"

    echo ""
}

# -----------------------------------------------------------------------------
# Alternative: Use 'last' command as fallback/supplement
# -----------------------------------------------------------------------------

extract_login_events_from_last() {
    local output_file="$1"

    log_info "Supplementing with 'last' command data..."

    # Use wtmp files for login history
    local wtmp_files=("/var/log/wtmp")

    # Add rotated wtmp files
    for rotated in /var/log/wtmp.[0-9]* /var/log/wtmp-*; do
        if [[ -f "$rotated" ]]; then
            wtmp_files+=("$rotated")
        fi
    done

    for wtmp_file in "${wtmp_files[@]}"; do
        if [[ -f "$wtmp_file" ]] && [[ -r "$wtmp_file" ]]; then
            last -f "$wtmp_file" 2>/dev/null | \
            grep -v '^$' | \
            grep -v '^wtmp' | \
            grep -v '^reboot' | \
            grep -v 'still logged in' | \
            awk '
            {
                username = $1
                if (username == "" || username == "reboot" || username == "shutdown") next

                # Parse date - format varies but typically: "Mon Jan  1 12:00"
                # Fields: username, terminal, source, day, month, date, time
                if (NF >= 7) {
                    month_str = $5
                    day = $6
                    time = $7

                    # Determine year - last command may not show year for current year
                    # We will need to infer or skip
                }
            }
            '
        fi
    done >> "$output_file" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Main Script
# -----------------------------------------------------------------------------

usage() {
    cat << EOF
${BOLD}User Login Report Script${NC}

${BOLD}USAGE:${NC}
    $(basename "$0") [YEAR]

${BOLD}ARGUMENTS:${NC}
    YEAR    Optional. 4-digit year (e.g., 2024)
            If not provided, shows current year summary report.

${BOLD}EXAMPLES:${NC}
    $(basename "$0")           # Current year: today, week, month, year logins
    $(basename "$0") 2024      # Month-wise breakdown for 2024
    $(basename "$0") 2023      # Month-wise breakdown for 2023

${BOLD}REQUIREMENTS:${NC}
    - Root/sudo access to read /var/log/audit/
    - auditd service running

${BOLD}OUTPUT:${NC}
    Without year argument:
        USERNAME     TODAY   THIS_WEEK   THIS_MONTH   THIS_YEAR
        john.doe        2           5           12          156

    With year argument:
        USERNAME    JAN  FEB  MAR  APR  MAY  JUN  JUL  AUG  SEP  OCT  NOV  DEC  TOTAL
        john.doe     10   12   15   14   16   12   10    8   14   15   16   14    156

EOF
    exit 0
}

main() {
    local target_year=""

    # Parse arguments
    case "${1:-}" in
        -h|--help|help)
            usage
            ;;
        "")
            # No argument - use current year summary mode
            target_year=""
            ;;
        *)
            target_year="$1"
            validate_year "$target_year"
            ;;
    esac

    # Check prerequisites
    check_prerequisites

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}       USER LOGIN REPORT${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo -e "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "Host: $(hostname)"
    echo ""

    # Determine the year to process
    local process_year
    if [[ -z "$target_year" ]]; then
        process_year=$(date '+%Y')
    else
        process_year="$target_year"
    fi

    # Extract login events for the target year only
    local events_file="$TEMP_DIR/login_events.txt"
    extract_login_events "$events_file" "$process_year"

    # Generate appropriate report
    if [[ -z "$target_year" ]]; then
        generate_current_year_report "$events_file"
    else
        generate_year_report "$events_file" "$target_year"
    fi

    echo -e "${BOLD}========================================${NC}"
    echo ""
}

# Run main function with all arguments
main "$@"
