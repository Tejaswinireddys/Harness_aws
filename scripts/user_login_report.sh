#!/bin/bash
#
# User Login Report Script for Amazon Linux 2023
# Analyzes /var/log/audit/ logs for user login statistics
#
# Usage:
#   ./user_login_report.sh          # Current year report (today, week, month, year)
#   ./user_login_report.sh 2024     # Month-wise report for specific year
#

set -o pipefail

# Configuration
AUDIT_LOG_DIR="/var/log/audit"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    NC='\033[0m'
else
    BOLD=''
    NC=''
fi

log_info() {
    echo -e "[INFO] $1" >&2
}

log_warn() {
    echo -e "[WARN] $1" >&2
}

log_error() {
    echo -e "[ERROR] $1" >&2
}

# -----------------------------------------------------------------------------
# Parse audit logs and extract login events
# -----------------------------------------------------------------------------
extract_login_events() {
    local output_file="$1"
    local target_year="$2"

    log_info "Extracting login events for year $target_year..."

    # Collect all audit log files
    local audit_files=()

    if [[ -f "$AUDIT_LOG_DIR/audit.log" ]]; then
        audit_files+=("$AUDIT_LOG_DIR/audit.log")
    fi

    # Add rotated logs
    for f in "$AUDIT_LOG_DIR"/audit.log.[0-9]*; do
        [[ -f "$f" ]] && audit_files+=("$f")
    done

    # Add compressed logs (decompress to temp)
    for f in "$AUDIT_LOG_DIR"/audit.log.*.gz; do
        if [[ -f "$f" ]]; then
            local temp_file="$TEMP_DIR/$(basename "$f" .gz)"
            zcat "$f" > "$temp_file" 2>/dev/null && audit_files+=("$temp_file")
        fi
    done

    if [[ ${#audit_files[@]} -eq 0 ]]; then
        log_error "No audit log files found in $AUDIT_LOG_DIR"
        touch "$output_file"
        return
    fi

    log_info "Found ${#audit_files[@]} audit log file(s)"

    # Parse login events - look for USER_LOGIN, USER_AUTH, USER_START with success
    cat "${audit_files[@]}" 2>/dev/null | \
    grep -E 'type=(USER_LOGIN|USER_AUTH|USER_START)' | \
    grep -i 'res=success' | \
    while read -r line; do
        # Extract epoch from msg=audit(EPOCH.xxx:xxx)
        epoch=$(echo "$line" | sed -n 's/.*msg=audit(\([0-9]*\).*/\1/p')
        [[ -z "$epoch" ]] && continue

        # Extract username from acct="xxx"
        username=$(echo "$line" | sed -n 's/.*acct="\([^"]*\)".*/\1/p')
        if [[ -z "$username" ]]; then
            username=$(echo "$line" | sed -n 's/.*acct=\([^ ]*\).*/\1/p' | tr -d '"')
        fi
        [[ -z "$username" || "$username" == "?" || "$username" == "(unknown)" ]] && continue

        # Skip system accounts
        case "$username" in
            nobody|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|sshd|systemd|messagebus|polkitd|chrony|dbus|rpc|rpcuser|nfsnobody|ec2-instance-connect|ssm-user|postfix)
                continue ;;
        esac

        # Convert epoch to date
        login_date=$(date -d "@$epoch" '+%Y-%m-%d' 2>/dev/null)
        [[ -z "$login_date" ]] && continue

        # Check year
        login_year="${login_date:0:4}"
        [[ "$login_year" != "$target_year" ]] && continue

        echo "$username|$login_date"
    done | sort -u > "$output_file"

    local count=$(wc -l < "$output_file" | tr -d ' ')
    log_info "Found $count login events for year $target_year"
}

# -----------------------------------------------------------------------------
# Generate current year report (today, week, month, year)
# -----------------------------------------------------------------------------
generate_current_year_report() {
    local events_file="$1"

    local today=$(date '+%Y-%m-%d')
    local current_year=$(date '+%Y')

    # Calculate week start (Monday)
    local day_of_week=$(date '+%u')
    local days_back=$((day_of_week - 1))
    local week_start=$(date -d "$today - $days_back days" '+%Y-%m-%d' 2>/dev/null || echo "$today")

    # Month start
    local month_start=$(date '+%Y-%m-01')

    log_info "Report period: Today=$today, Week start=$week_start, Month start=$month_start"

    if [[ ! -s "$events_file" ]]; then
        echo ""
        echo "No login data found for $current_year"
        return
    fi

    # Get unique users
    cut -d'|' -f1 "$events_file" | sort -u > "$TEMP_DIR/users.txt"

    echo ""
    printf "${BOLD}%-25s %10s %12s %12s %12s${NC}\n" "USERNAME" "TODAY" "THIS_WEEK" "THIS_MONTH" "THIS_YEAR"
    printf "%-25s %10s %12s %12s %12s\n" "-------------------------" "----------" "------------" "------------" "------------"

    # Calculate stats per user
    while read -r username; do
        [[ -z "$username" ]] && continue

        local today_count=0 week_count=0 month_count=0 year_count=0

        while IFS='|' read -r user login_date; do
            [[ "$user" != "$username" ]] && continue

            ((year_count++))

            if [[ "$login_date" == "$today" ]]; then
                ((today_count++))
            fi

            if [[ ! "$login_date" < "$week_start" ]]; then
                ((week_count++))
            fi

            if [[ ! "$login_date" < "$month_start" ]]; then
                ((month_count++))
            fi
        done < "$events_file"

        if [[ $year_count -gt 0 ]]; then
            printf "%-25s %10d %12d %12d %12d\n" "$username" "$today_count" "$week_count" "$month_count" "$year_count"
        fi
    done < "$TEMP_DIR/users.txt" | sort -t' ' -k5 -nr

    # Totals
    local total_today=0 total_week=0 total_month=0 total_year=0

    while IFS='|' read -r user login_date; do
        [[ -z "$login_date" ]] && continue
        ((total_year++))
        [[ "$login_date" == "$today" ]] && ((total_today++))
        [[ ! "$login_date" < "$week_start" ]] && ((total_week++))
        [[ ! "$login_date" < "$month_start" ]] && ((total_month++))
    done < "$events_file"

    printf "%-25s %10s %12s %12s %12s\n" "-------------------------" "----------" "------------" "------------" "------------"
    printf "${BOLD}%-25s %10d %12d %12d %12d${NC}\n" "TOTAL" "$total_today" "$total_week" "$total_month" "$total_year"
    echo ""
}

# -----------------------------------------------------------------------------
# Generate year report (month-wise breakdown)
# -----------------------------------------------------------------------------
generate_year_report() {
    local events_file="$1"
    local target_year="$2"

    log_info "Generating month-wise report for $target_year..."

    if [[ ! -s "$events_file" ]]; then
        echo ""
        echo "No login data found for $target_year"
        return
    fi

    # Calculate monthly stats per user
    awk -F'|' '
    {
        user = $1
        date = $2
        split(date, d, "-")
        month = int(d[2])
        key = user "|" month
        count[key]++
        users[user] = 1
    }
    END {
        for (u in users) {
            printf "%s", u
            total = 0
            for (m = 1; m <= 12; m++) {
                c = count[u "|" m] + 0
                printf "|%d", c
                total += c
            }
            printf "|%d\n", total
        }
    }
    ' "$events_file" | sort -t'|' -k14 -nr > "$TEMP_DIR/monthly.txt"

    # Print header
    echo ""
    printf "${BOLD}%-15s" "USERNAME"
    for m in JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC; do
        printf " %4s" "$m"
    done
    printf " %6s${NC}\n" "TOTAL"

    printf "%-15s" "---------------"
    for i in {1..12}; do printf " %4s" "----"; done
    printf " %6s\n" "------"

    # Print data
    local t1=0 t2=0 t3=0 t4=0 t5=0 t6=0 t7=0 t8=0 t9=0 t10=0 t11=0 t12=0 grand=0

    while IFS='|' read -r user m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 total; do
        [[ -z "$user" ]] && continue
        printf "%-15s %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %6d\n" \
            "$user" "$m1" "$m2" "$m3" "$m4" "$m5" "$m6" "$m7" "$m8" "$m9" "$m10" "$m11" "$m12" "$total"

        ((t1+=m1)); ((t2+=m2)); ((t3+=m3)); ((t4+=m4)); ((t5+=m5)); ((t6+=m6))
        ((t7+=m7)); ((t8+=m8)); ((t9+=m9)); ((t10+=m10)); ((t11+=m11)); ((t12+=m12))
        ((grand+=total))
    done < "$TEMP_DIR/monthly.txt"

    printf "%-15s" "---------------"
    for i in {1..12}; do printf " %4s" "----"; done
    printf " %6s\n" "------"

    printf "${BOLD}%-15s %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %6d${NC}\n" \
        "TOTAL" "$t1" "$t2" "$t3" "$t4" "$t5" "$t6" "$t7" "$t8" "$t9" "$t10" "$t11" "$t12" "$grand"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
usage() {
    cat << 'EOF'
User Login Report Script

USAGE:
    ./user_login_report.sh [YEAR]

EXAMPLES:
    ./user_login_report.sh           # Current year summary
    ./user_login_report.sh 2024      # Month-wise for 2024
    ./user_login_report.sh 2025      # Month-wise for 2025

REQUIREMENTS:
    - Root/sudo access to read /var/log/audit/
    - auditd service running
EOF
    exit 0
}

main() {
    local target_year=""

    case "${1:-}" in
        -h|--help|help) usage ;;
        "") target_year="" ;;
        *)
            if [[ ! "$1" =~ ^[0-9]{4}$ ]]; then
                log_error "Invalid year: $1 (must be 4-digit year)"
                exit 1
            fi
            target_year="$1"
            ;;
    esac

    # Check prerequisites
    if [[ ! -d "$AUDIT_LOG_DIR" ]]; then
        log_error "Audit log directory not found: $AUDIT_LOG_DIR"
        exit 1
    fi

    if [[ ! -r "$AUDIT_LOG_DIR/audit.log" ]]; then
        log_error "Cannot read audit logs. Run with sudo."
        exit 1
    fi

    # Determine year
    local process_year
    if [[ -z "$target_year" ]]; then
        process_year=$(date '+%Y')
    else
        process_year="$target_year"
    fi

    echo ""
    echo -e "${BOLD}================================================${NC}"
    echo -e "${BOLD}         USER LOGIN REPORT${NC}"
    echo -e "${BOLD}================================================${NC}"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname)"
    echo ""

    # Extract events
    local events_file="$TEMP_DIR/events.txt"
    extract_login_events "$events_file" "$process_year"

    # Generate report
    if [[ -z "$target_year" ]]; then
        generate_current_year_report "$events_file"
    else
        generate_year_report "$events_file" "$target_year"
    fi

    echo -e "${BOLD}================================================${NC}"
    echo ""
}

main "$@"
