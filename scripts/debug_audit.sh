#!/bin/bash
# Debug script to check audit log format

echo "=== Checking audit log files ==="
ls -la /var/log/audit/

echo ""
echo "=== Sample USER_LOGIN/USER_START events (first 5) ==="
grep -E 'type=(USER_LOGIN|USER_START)' /var/log/audit/audit.log 2>/dev/null | head -5

echo ""
echo "=== Sample successful login events ==="
grep -E 'type=(USER_LOGIN|USER_START)' /var/log/audit/audit.log 2>/dev/null | grep -i 'res=success' | head -5

echo ""
echo "=== All unique event types in audit log ==="
grep -oE 'type=[A-Z_]+' /var/log/audit/audit.log 2>/dev/null | sort -u | head -20

echo ""
echo "=== Count of login-related events ==="
echo "USER_LOGIN events: $(grep -c 'type=USER_LOGIN' /var/log/audit/audit.log 2>/dev/null || echo 0)"
echo "USER_START events: $(grep -c 'type=USER_START' /var/log/audit/audit.log 2>/dev/null || echo 0)"
echo "USER_AUTH events: $(grep -c 'type=USER_AUTH' /var/log/audit/audit.log 2>/dev/null || echo 0)"
echo "CRED_ACQ events: $(grep -c 'type=CRED_ACQ' /var/log/audit/audit.log 2>/dev/null || echo 0)"

echo ""
echo "=== Check last command output ==="
last | head -10
