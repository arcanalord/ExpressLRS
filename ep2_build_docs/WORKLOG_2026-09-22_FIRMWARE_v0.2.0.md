# WORKLOG — EP2 LINK firmware v0.2.0 — 2026-09-22

## Completed
- official ExpressLRS Generic 2400 GPIO mapping re-verified;
- firmware architecture kept as one binary for A/B, node ID in EEPROM;
- corrected RadioLib SX1280 begin arguments;
- added retries, timeout/loss, duplicate suppression, BUSY protection and diagnostics;
- embedded UNIFIED_ESP8285_2400_RX marker;
- own Wi-Fi OTA validates target marker;
- clarified first stock-ELRS transition: prefer raw .bin, not gzip;
- isolated build branch created; master untouched;
- real GitHub Actions ESP8285 compilation completed successfully;
- produced raw bin, gzip and manifest;
- hashes and marker independently rechecked after artifact download;
- compiled artifact uploaded to Dropbox 05_Релизы.

## Current gate
EP2_BUILD_PASS = PASS

## Next physical sequence
1. Keep EP2-B stock.
2. Confirm recovery path and exact physical revision of EP2-A.
3. Flash raw v0.2.0 BIN to EP2-A.
4. Verify READY / INFO / RADIO_OK.
5. Set NODE 1.
6. Verify own WIFI_UPDATE by reflashing same raw BIN.
7. Only then convert EP2-B and set NODE 2.
8. Run 100 then 1000 PING/PONG packets and record RSSI/SNR/RTT/retry/loss.
