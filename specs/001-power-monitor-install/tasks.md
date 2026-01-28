# Tasks: Power Monitor Installation

**Input**: Design documents from `/specs/001-power-monitor-install/`
**Prerequisites**: plan.md, spec.md (user stories), research.md, data-model.md, contracts/

**Tests**: This feature uses manual hardware validation testing (not automated unit tests). See quickstart.md for validation procedures.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each power management capability.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- **scripts/**: Installation scripts at repository root
- **scripts/templates/**: Service files and monitoring scripts
- **tests/**: Hardware validation scripts

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare directory structure and copy reference implementation files

- [X] T001 Create scripts/templates/ directory for service files and monitoring scripts
- [X] T002 [P] Copy witty_pi_monitor.sh from /home/chadagate/edge-sensor/scripts/ to scripts/templates/
- [X] T003 [P] Copy daily_7am_to_930pm.wpi from /home/chadagate/edge-sensor/scripts/ to scripts/templates/
- [X] T004 [P] Copy systemd service files from specs/001-power-monitor-install/contracts/ to scripts/templates/ (power-monitor.service, wittypi-firstboot.service, wittypi-rtc-sync.service, wittypi-rtc-sync.timer, wittypi-rtc-sync-daily.service)
- [X] T005 Create tests/ directory for hardware validation scripts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core installation script infrastructure that MUST be complete before ANY user story implementation

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Add system package installation for i2c-tools and python3-smbus to install_system_packages() function in scripts/install.sh
- [X] T006b Enable I2C interface via raspi-config nonint do_i2c 0 in configure_wittypi() function in scripts/install.sh and verify /dev/i2c-1 exists after enablement
- [X] T007 Create configure_wittypi() skeleton function in scripts/install.sh with non-fatal error handling pattern
- [X] T008 Create install_power_monitor() skeleton function in scripts/install.sh with non-fatal error handling pattern
- [X] T009 Add configure_wittypi() and install_power_monitor() calls to main() function in scripts/install.sh (after configure_4g_modem, before display_summary)
- [X] T010 Update display_summary() function in scripts/install.sh to add WittyPi and power monitor status sections

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - WittyPi Installation and Auto-Boot Configuration (Priority: P1) 🎯 MVP

**Goal**: Field technicians can run install script and have WittyPi auto-boot configured automatically, enabling devices to power on without manual intervention after power loss

**Independent Test**: Run install script on Raspberry Pi with WittyPi 4 Mini connected, reboot, power cycle device, verify auto-boot (power on without button press within 5 seconds)

### Implementation for User Story 1

- [X] T011 [US1] Implement WittyPi directory creation and download logic in configure_wittypi() function in scripts/install.sh (create /opt/wittypi, wget install.sh from uugear.com)
- [X] T012 [US1] Implement WittyPi installer execution with progress logging in configure_wittypi() function in scripts/install.sh (run install.sh, log to /tmp/wittypi_install.log)
- [X] T013 [US1] Implement WittyPi installation verification in configure_wittypi() function in scripts/install.sh (check /opt/wittypi/wittypi/utilities.sh exists)
- [X] T014 [US1] Implement NTP re-enable logic in configure_wittypi() function in scripts/install.sh (timedatectl set-ntp true after WittyPi installation)
- [X] T015 [US1] Implement wittypi-firstboot.service installation in configure_wittypi() function in scripts/install.sh (copy from templates/, set permissions 644, enable service)
- [X] T016 [US1] Add WittyPi status display to display_summary() function in scripts/install.sh (show installation status, first-boot service status, auto-boot pending message)
- [X] T017 [US1] Add REBOOT_REQUIRED=true flag when WittyPi configured in configure_wittypi() function in scripts/install.sh
- [ ] T018 [US1] Add wittypi_configured rollback step to rollback() function in scripts/install.sh (disable services, remove /opt/wittypi, daemon-reload)

**Checkpoint**: WittyPi installation and auto-boot configuration complete - Test independently per quickstart.md Test 1

---

## Phase 4: User Story 2 - RTC Time Synchronization (Priority: P2)

**Goal**: System administrators have accurate RTC time that persists across power cycles, ensuring power monitoring logs have correct timestamps even when network unavailable

**Independent Test**: Set system time via NTP, sync to RTC, disconnect network, power cycle device, verify system time restored from RTC (time match within 2 seconds)

### Implementation for User Story 2

- [X] T019 [P] [US2] Implement wittypi-rtc-sync.service installation in configure_wittypi() function in scripts/install.sh (copy from templates/, set permissions 644, enable for shutdown targets)
- [X] T020 [P] [US2] Implement wittypi-rtc-sync.timer and wittypi-rtc-sync-daily.service installation in configure_wittypi() function in scripts/install.sh (copy from templates/, set permissions 644, enable timer)
- [X] T021 [US2] Add RTC sync service status to display_summary() function in scripts/install.sh (show shutdown sync status, daily timer status, NTP status)
- [ ] T022 [US2] Update wittypi_configured rollback step in rollback() function in scripts/install.sh to include RTC sync services removal

**Checkpoint**: RTC synchronization services installed - Test independently per quickstart.md Test 2

---

## Phase 5: User Story 3 - Power Schedule Configuration (Priority: P3)

**Goal**: Fleet operators have devices that automatically power on at 7 AM and off at 9:30 PM daily, conserving battery during non-operating hours

**Independent Test**: Verify schedule.wpi file copied and processed, check runScript.sh log for 7 AM / 9:30 PM times, optionally monitor device at scheduled shutdown/startup times

### Implementation for User Story 3

- [X] T023 [US3] Implement power schedule file check and copy logic in configure_wittypi() function in scripts/install.sh (check daily_7am_to_930pm.wpi exists, copy to schedules/ and schedule.wpi)
- [X] T024 [US3] Implement schedule processing with runScript.sh in configure_wittypi() function in scripts/install.sh (cd to wittypi dir, run runScript.sh, log output to schedule.log)
- [X] T024b [US3] Verify schedule processing by parsing runScript.sh output or schedule.log for expected startup time (7:00 or 07:00) and shutdown time (21:30 or 9:30 PM) to ensure ±2 minute accuracy requirement
- [X] T025 [US3] Add schedule file missing edge case handling in configure_wittypi() function in scripts/install.sh (log warning if file not found, continue installation)
- [X] T026 [US3] Add power schedule status to display_summary() function in scripts/install.sh (show schedule installed status, display "7:00 AM to 9:30 PM local time" message)

**Checkpoint**: Power schedule configured - Test independently per quickstart.md Test 5

---

## Phase 6: User Story 4 - Power Monitor Service Installation (Priority: P2)

**Goal**: System administrators have continuous power consumption logging from INA219 sensor, enabling battery health monitoring and power usage analysis

**Independent Test**: Verify power-monitor.service running, check /var/log/power_daily/power_YYYY-MM-DD.csv contains voltage/current/power data with 60-second intervals

### Implementation for User Story 4

- [X] T027 [US4] Create /opt/power-monitor directory and /var/log/power_daily directory in install_power_monitor() function in scripts/install.sh
- [X] T028 [US4] Implement witty_pi_monitor.sh copy logic in install_power_monitor() function in scripts/install.sh (copy from templates/, set executable permissions 755, set root ownership)
- [X] T028b [US4] Implement 30-day log retention logic in witty_pi_monitor.sh by adding cleanup code that deletes files older than 30 days from /var/log/power_daily before logging new data (use find command with -mtime +30 -delete)
- [X] T029 [US4] Implement power-monitor.service installation in install_power_monitor() function in scripts/install.sh (copy from templates/, set permissions 644, systemctl daemon-reload)
- [X] T030 [US4] Implement power-monitor.service enable and start logic in install_power_monitor() function in scripts/install.sh (systemctl enable/start, check is-active status)
- [X] T031 [US4] Add python3-smbus installation failure edge case handling in install_power_monitor() function in scripts/install.sh (log warning if python3-smbus fails, continue without INA219 support)
- [X] T032 [US4] Add service startup failure edge case handling in install_power_monitor() function in scripts/install.sh (log warning if service fails to start, display troubleshooting hint in summary)
- [X] T033 [US4] Add power monitor status to display_summary() function in scripts/install.sh (show service status, data directory path, log viewing command)
- [ ] T034 [US4] Add power_monitor_configured rollback step to rollback() function in scripts/install.sh (disable service, stop service, remove /opt/power-monitor, keep /var/log/power_daily for analysis)

**Checkpoint**: Power monitoring service installed and logging data - Test independently per quickstart.md Test 3, Test 4

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [X] T035 [P] Add edge case handling for /opt/wittypi directory already exists in configure_wittypi() function in scripts/install.sh (skip download, log info, use existing installation)
- [X] T036 [P] Add error handling for uugear.com download failure in configure_wittypi() function in scripts/install.sh (log warning, return 0 for non-fatal, provide manual installation command in summary)
- [X] T037 [P] Add comprehensive error logging with actionable messages throughout configure_wittypi() and install_power_monitor() functions in scripts/install.sh
- [ ] T038 Create test_power_monitor_install.sh validation script in tests/ directory (automate hardware detection checks, service status checks, log file verification per quickstart.md)
- [X] T039 Update installation summary reboot warning in display_summary() function in scripts/install.sh to include WittyPi I2C configuration message
- [ ] T040 Run full hardware validation test suite per quickstart.md (all 7 tests: auto-boot, RTC sync, power monitoring, service restart, power schedule, log rotation, graceful degradation)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational (Phase 2) completion
  - US1 (WittyPi Installation) - No dependencies on other stories
  - US2 (RTC Sync) - Depends on US1 (requires WittyPi installed and configure_wittypi() function)
  - US3 (Power Schedule) - Depends on US1 (requires WittyPi installed and configure_wittypi() function)
  - US4 (Power Monitor) - Depends on US1 (requires WittyPi for 5V supply readings, but INA219 independent)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - FOUNDATIONAL for US2, US3, US4
- **User Story 2 (P2)**: Can start after US1 complete (requires configure_wittypi() function and WittyPi installed)
- **User Story 3 (P3)**: Can start after US1 complete (requires configure_wittypi() function and WittyPi installed)
- **User Story 4 (P2)**: Can start after US1 complete (WittyPi provides 5V supply metrics, but can proceed in parallel with US2/US3)

### Within Each User Story

- US1: Directory setup → Download → Installation → Verification → Service creation → Summary display → Rollback handling
- US2: Service installation (parallel) → Summary display → Rollback update
- US3: File check → Copy → Process → Edge cases → Summary display
- US4: Directory creation → Script copy → Service installation → Enable/Start → Edge cases → Summary display → Rollback handling

### Parallel Opportunities

- **Phase 1 Setup**: T002, T003, T004 (file copying) can run in parallel
- **Phase 2 Foundational**: T006 and T010 can run in parallel (different functions)
- **Phase 4 US2**: T019 and T020 (different service files) can run in parallel
- **Phase 7 Polish**: T035, T036, T037 (different edge cases) can run in parallel
- **User Stories**: After US1 complete, US2, US3, US4 can proceed in parallel if team capacity allows (US2 and US3 modify same function but different sections)

---

## Parallel Example: User Story 2 (RTC Sync)

```bash
# Launch both service installations together:
Task: "Implement wittypi-rtc-sync.service installation in configure_wittypi() function in scripts/install.sh"
Task: "Implement wittypi-rtc-sync.timer and wittypi-rtc-sync-daily.service installation in configure_wittypi() function in scripts/install.sh"

# These tasks write to different systemd service files and can execute concurrently
```

---

## Parallel Example: Phase 1 Setup

```bash
# Launch all file copying tasks together:
Task: "Copy witty_pi_monitor.sh from /home/chadagate/edge-sensor/scripts/ to scripts/templates/"
Task: "Copy daily_7am_to_930pm.wpi from /home/chadagate/edge-sensor/scripts/ to scripts/templates/"
Task: "Copy systemd service files from specs/001-power-monitor-install/contracts/ to scripts/templates/"

# These tasks operate on different source files and can execute concurrently
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Minimum Viable Product = Auto-Boot Working**

1. Complete Phase 1: Setup (T001-T005) - ~10 minutes
2. Complete Phase 2: Foundational (T006-T010) - ~30 minutes
3. Complete Phase 3: User Story 1 (T011-T018) - ~2 hours
4. **STOP and VALIDATE**: Run quickstart.md Test 1 (WittyPi auto-boot verification)
   - Install script on Pi with WittyPi connected
   - Reboot device
   - Power cycle and verify auto-boot within 5 seconds
5. Deploy if ready (devices will auto-boot reliably)

**Value Delivered**: Field deployments can survive power loss without manual intervention

---

### Incremental Delivery (All User Stories)

**Full Feature Set = Complete Power Management**

1. **Foundation** (Phase 1-2): Setup + Foundational → ~40 minutes
2. **US1 - Auto-Boot** (Phase 3): T011-T018 → Test independently → Deploy/Demo (~2 hours)
   - **Value**: Devices auto-boot on power restore
3. **US2 - RTC Sync** (Phase 4): T019-T022 → Test independently → Deploy/Demo (~1 hour)
   - **Value**: Accurate timestamps offline
4. **US3 - Power Schedule** (Phase 5): T023-T026 → Test independently → Deploy/Demo (~1.5 hours)
   - **Value**: Battery conservation (9.5 hours off daily)
5. **US4 - Power Monitoring** (Phase 6): T027-T034 → Test independently → Deploy/Demo (~2.5 hours)
   - **Value**: Battery health insights, power usage trends
6. **Polish** (Phase 7): T035-T040 → Final validation → Production release (~2 hours)
   - **Value**: Production-ready with edge case handling

**Total Implementation Time**: ~10.5 hours for full feature set (includes I2C enablement, schedule validation, and log rotation)

**Each story adds value without breaking previous stories**

---

### Parallel Team Strategy

With 2 developers after US1 complete:

1. **Team completes US1 together** (blocking prerequisite for US2, US3, US4)
2. Once US1 done:
   - **Developer A**: US2 (RTC Sync) + US3 (Power Schedule) - Both modify configure_wittypi() but different sections
   - **Developer B**: US4 (Power Monitor) - Modifies install_power_monitor(), independent function
3. Stories complete and integrate independently
4. Both developers join for Phase 7 (Polish) validation

**Parallel Speedup**: ~7.5 hours total with 2 developers (vs 10.5 hours solo)

---

## Task Summary

- **Total Tasks**: 43
- **Setup Tasks**: 5 (Phase 1)
- **Foundational Tasks**: 6 (Phase 2) - includes I2C enablement
- **User Story 1 (P1)**: 8 tasks - WittyPi Installation and Auto-Boot
- **User Story 2 (P2)**: 4 tasks - RTC Time Synchronization
- **User Story 3 (P3)**: 5 tasks - Power Schedule Configuration (includes schedule validation)
- **User Story 4 (P2)**: 9 tasks - Power Monitor Service (includes log rotation)
- **Polish Tasks**: 6 (Phase 7)
- **Parallel Opportunities**: 8 tasks marked [P] (19% can run concurrently)

---

## Notes

- [P] tasks = different files or independent sections, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently per quickstart.md
- **Hardware Required**: WittyPi 4 Mini + INA219 + Battery for full validation
- **Testing**: Manual hardware validation (not automated unit tests) - see quickstart.md for 7 validation tests
- **Reference Implementation**: /home/chadagate/edge-sensor/scripts/install.sh lines 1227-1624 (proven in 800+ deployments)
