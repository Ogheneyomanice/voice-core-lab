#!/usr/bin/env bash
# System and acceptance tests for the voice core lab, driven by SIPp.
#
# Environment variables:
#   TARGET  host name or IP of the SIP proxy (default: kamailio)
#   PORT    SIP port (default: 5060)
#   TESTS   space separated list: options register call (default: all)
#   RESULTS directory for logs and summary.txt (default: /results)

set -u

TARGET="${TARGET:-kamailio}"
PORT="${PORT:-5060}"
TESTS="${TESTS:-options register call}"
RESULTS="${RESULTS:-/results}"

mkdir -p "$RESULTS"
SUMMARY="$RESULTS/summary.txt"
: > "$SUMMARY"
FAILED=0

record() {
    # $1 = test name, $2 = exit code
    if [ "$2" -eq 0 ]; then
        echo "PASS  $1" | tee -a "$SUMMARY"
    else
        echo "FAIL  $1 (exit code $2)" | tee -a "$SUMMARY"
        FAILED=1
    fi
}

wait_until_ready() {
    echo "Waiting for $TARGET:$PORT ..."
    for i in $(seq 1 30); do
        if timeout 5 sipp "$TARGET:$PORT" -sf /scenarios/options.xml -m 1 -p 5070 -nostdin >/dev/null 2>&1; then
            echo "SIP proxy is up."
            return 0
        fi
        sleep 1
    done
    echo "FAIL  startup: $TARGET:$PORT did not answer within 30 seconds" | tee -a "$SUMMARY"
    return 1
}

t_options() {
    timeout 20 sipp "$TARGET:$PORT" -sf /scenarios/options.xml -m 1 -p 5070 -nostdin \
        > "$RESULTS/options.log" 2>&1
    record "S1 options: proxy answers 200 OK to OPTIONS" $?
}

t_register() {
    timeout 20 sipp "$TARGET:$PORT" -sf /scenarios/register.xml -m 1 -p 5063 -nostdin \
        > "$RESULTS/register.log" 2>&1
    record "S2 register: user bob registers and gets 200 OK" $?
}

t_call() {
    # Bob's phone: SIPp built-in UAS, listens on 5062 and answers one call.
    timeout 40 sipp -sn uas -p 5062 -m 1 -nostdin > "$RESULTS/call-bob-uas.log" 2>&1 &
    UAS_PID=$!
    sleep 1

    # Bob registers with contact <sip:bob@this-host:5062>.
    timeout 20 sipp "$TARGET:$PORT" -sf /scenarios/register.xml -m 1 -p 5063 -nostdin \
        > "$RESULTS/call-register.log" 2>&1

    # Alice's phone: SIPp built-in UAC calls bob through the proxy, talks 1 s, hangs up.
    timeout 30 sipp "$TARGET:$PORT" -sn uac -s bob -m 1 -p 5061 -d 1000 -nostdin \
        > "$RESULTS/call-alice-uac.log" 2>&1
    UAC_RC=$?

    wait "$UAS_PID"
    UAS_RC=$?

    RC=0
    if [ "$UAC_RC" -ne 0 ] || [ "$UAS_RC" -ne 0 ]; then
        RC=1
    fi
    record "A1 call: alice calls bob through the proxy (INVITE, 180, 200, ACK, BYE)" "$RC"
}

wait_until_ready || exit 1

for t in $TESTS; do
    case "$t" in
        options)  t_options ;;
        register) t_register ;;
        call)     t_call ;;
        *)        echo "Unknown test: $t" | tee -a "$SUMMARY"; FAILED=1 ;;
    esac
done

echo
echo "===== Summary ====="
cat "$SUMMARY"
exit "$FAILED"
