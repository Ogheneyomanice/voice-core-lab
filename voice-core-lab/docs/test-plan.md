# Test plan

Tests are grouped the way a delivery project groups them: module tests check one
component, system tests check the deployed whole, acceptance tests check that the
service does what a user expects.

| ID | Level | What is checked | Pass criterion | How it runs |
|----|-------|-----------------|----------------|-------------|
| M1 | Module | Kamailio configuration is valid | `kamailio -c` exits 0 | Automatic, during `docker build` |
| S1 | System | Proxy is up and answers OPTIONS | 200 OK | `tests/run_tests.sh` (SIPp) |
| S2 | System | A user can register | 200 OK to REGISTER | `tests/run_tests.sh` (SIPp) |
| A1 | Acceptance | Alice can call a registered Bob | INVITE, 180, 200, ACK, BYE all complete | `tests/run_tests.sh` (SIPp) |
| S3 | System | Failover across availability zones (AWS) | After stopping one node, a new registration and call through the load balancer still succeed | Manual, steps below |
| L1 | System | Load | 100 calls at 10 calls per second complete with no failures | Manual, command below |

## S3: failover test on AWS (manual)

1. Run S2 and A1 against the load balancer name. Record the result.
2. In the EC2 console, stop one of the two `voicecore-kamailio` instances.
3. Wait about 30 seconds for the load balancer health check to mark it unhealthy.
4. Register again and place a call. This must pass, because registrations are kept in memory on each node, so the client has to register again after a node is lost.
5. Start the instance again, confirm it becomes healthy, and record the result.

## L1: load test (manual, local lab)

Run these in two terminals, inside the `tests` container or anywhere SIPp is installed:

```bash
# terminal 1: bob answers 100 calls
sipp -sn uas -p 5062 -m 100 -nostdin

# terminal 2: register bob once, then place 100 calls at 10 per second
sipp kamailio:5060 -sf /scenarios/register.xml -m 1 -p 5063 -nostdin
sipp kamailio:5060 -sn uac -s bob -r 10 -m 100 -d 500 -p 5061 -nostdin
```

## Results

Paste your real output here after you run the tests. Do not fill this in by hand.

```
(paste the contents of results/summary.txt)
```
