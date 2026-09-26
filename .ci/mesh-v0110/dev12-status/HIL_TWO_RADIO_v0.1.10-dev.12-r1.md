# HIL — two physical radio nodes

Target: Mesh Messenger Flutter v0.1.10-dev.12-r1

## What is automatic
Each app instance that has a ready MM-UART/1 + MMRP/1 session automatically responds to HIL traffic.
No button is required on the second phone.

The initiating phone verifies:
- 100 or 1000 request/reply probes;
- RTT min / average / max;
- loss;
- retries;
- final recipient ACK;
- repeated same messageId is marked duplicate;
- MapPoint payload survives the round trip;
- firmware statistics before/after when GET_STATS is available.

## Test 100
Use first. Expected result:
PASS · 100/100 · loss 0.0% · ACK PASS · dedupe PASS · MapPoint PASS

## Test 1000
Run only after Test 100 passes. It is the longer stability gate.

## Reconnect gate
After Test 100:
- unplug USB on one node;
- wait for app to show disconnected;
- reconnect USB;
- wait for MM-UART/1 + MMRP/1;
- run Test 100 again.

## Firmware compatibility
Preferred: M03 framework v0.4.1-dev or newer with COMPAT_SELFTEST.
Also supported by dev.12-r1: v0.4.0 without COMPAT_SELFTEST, provided HELLO/GET_INFO/GET_CAPS/GET_STATE establish a ready session and GET_CAPS explicitly advertises MMRP/1.

## Do not claim
Do not mark RADIO_HIL_PASS from the software simulator alone.
RADIO_HIL_PASS requires two physical radio boards.
