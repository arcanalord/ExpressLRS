# Main Mesh Messenger — Change Checklist

## Before
- [ ] Confirm this is main Mesh Messenger, not WiFi_First.
- [ ] Read NEXT_TASK.md.
- [ ] Confirm exact baseline and source hash.
- [ ] Identify one state owner being changed.
- [ ] Choose refactor OR behavior change, not both.

## During
- [ ] Keep diff small.
- [ ] Do not duplicate state ownership.
- [ ] Keep Web/Linux and Android shared assets synchronized.
- [ ] Do not touch unrelated sectors.
- [ ] Update tests for contract changes.

## Automated verification
- [ ] JS syntax
- [ ] source audit
- [ ] deterministic tests
- [ ] startup/navigation smoke
- [ ] sector regression
- [ ] Android contract checks
- [ ] Gradle build
- [ ] APK verify

## Runtime
- [ ] Android startup
- [ ] navigation
- [ ] changed function/UI
- [ ] lifecycle/back when relevant
- [ ] real hardware when radio behavior changed

## Promotion
- [ ] Draft PR reviewed
- [ ] CI evidence recorded
- [ ] runtime evidence recorded
- [ ] source/APK SHA-256 recorded
- [ ] CURRENT/STATUS/WORKLOG/BUILD_MANIFEST updated in Dropbox
- [ ] previous baseline archived, not destroyed
