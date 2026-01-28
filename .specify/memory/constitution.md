<!--
═══════════════════════════════════════════════════════════════════════════════
SYNC IMPACT REPORT
═══════════════════════════════════════════════════════════════════════════════
Version Change: None → 1.0.0
Rationale: Initial constitution creation for vision-sensor edge deployment project

Modified Principles: N/A (initial creation)
Added Sections:
  - Core Principles (5 principles)
    I. Edge-First Design
    II. Resource Constraint Discipline
    III. Reliability & Graceful Degradation
    IV. Security-by-Default
    V. Observable Operations
  - Deployment Standards
  - Development Workflow
  - Governance

Removed Sections: N/A (initial creation)

Templates Requiring Updates:
  ✅ plan-template.md - Constitution Check section exists, ready to use
  ✅ spec-template.md - Requirements section compatible with principles
  ✅ tasks-template.md - Task organization supports edge deployment patterns

Follow-up TODOs: None

Next Steps:
  - Use this constitution to guide feature specifications via /speckit.specify
  - Ensure all design artifacts reference these principles
  - Review compliance during implementation planning via /speckit.plan
═══════════════════════════════════════════════════════════════════════════════
-->

# Vision Sensor Constitution

## Core Principles

### I. Edge-First Design

Every feature MUST be designed for autonomous edge operation with intermittent connectivity.

- Network connectivity is OPTIONAL, not required for core functionality
- Local processing and decision-making take precedence over cloud dependencies
- All critical operations MUST work offline and sync when connectivity is restored
- Remote management capabilities are additive, not foundational

**Rationale**: Edge sensors deployed for AV ridehail detection operate in variable network conditions. Features that require constant connectivity will fail in the field, causing missed detections and operational gaps.

### II. Resource Constraint Discipline

All code MUST respect the hardware limitations of Raspberry Pi Zero 2W deployment targets.

- Maximum memory footprint: 200MB for the application (512MB total system RAM)
- CPU usage: Target <50% average to allow headroom for detection spikes
- Video processing: 640x480 @ 15fps is the baseline; higher resolutions require explicit justification
- Storage: Assume 8GB minimum available; implement log rotation and image cleanup
- Startup time: Application MUST be operational within 60 seconds of system boot

**Rationale**: Pi Zero 2W has 512MB RAM and limited CPU. Resource-hungry features cause frame drops, missed detections, system instability, and field deployment failures.

### III. Reliability & Graceful Degradation

System MUST maintain core detection capabilities even when subsystems fail.

- Camera disconnection/failure MUST NOT crash the application; retry with exponential backoff
- Storage full conditions MUST trigger automatic cleanup (oldest first) rather than blocking operations
- Network unavailability MUST queue telemetry locally and sync when restored
- Configuration errors MUST fall back to safe defaults with clear error logging
- The system MUST recover automatically from transient failures without manual intervention

**Rationale**: Edge sensors are deployed in remote locations with limited physical access. Manual intervention for every failure is operationally infeasible. The system must be self-healing.

### IV. Security-by-Default

All features MUST be secure for deployment on public-facing edge devices.

- NO default passwords in production builds; force configuration during setup
- Authentication required for ALL management interfaces (web UI, API endpoints)
- Credentials stored encrypted; plaintext secrets prohibited in code or config files
- HTTPS enforced for remote access; HTTP redirects to HTTPS
- Minimal attack surface: Disable unused services, close unnecessary ports
- Security updates MUST be deployable remotely without physical device access

**Rationale**: Sensors deployed for ridehail detection are installed in public or semi-public spaces and are attractive targets for tampering, unauthorized access, or hijacking. Security cannot be bolted on later.

### V. Observable Operations

All deployments MUST provide remote visibility into system health and detection performance.

- Structured logging (JSON format) for all critical operations, errors, and detections
- Health check endpoint exposing: uptime, camera status, disk usage, memory usage, detection count
- Detection events logged with timestamps, confidence scores, and frame metadata
- Error conditions surfaced with actionable context (not just stack traces)
- Log retention: 7 days local, with remote log shipping when connectivity available

**Rationale**: Debugging edge deployments without observability requires physical site visits. Rich, structured logging enables remote diagnosis, performance monitoring, and early detection of degradation.

## Deployment Standards

### Hardware Requirements

- **Minimum Platform**: Raspberry Pi Zero 2W (512MB RAM, quad-core ARM)
- **Camera**: USB-compatible, 640x480 minimum resolution
- **Storage**: 8GB microSD minimum (16GB recommended)
- **Network**: Optional 4G LTE or WiFi for remote management

### Software Standards

- **Runtime**: Python 3.11+ (leveraging performance improvements)
- **Dependency Management**: Poetry for reproducible builds
- **Service Management**: systemd for automatic startup and restart on failure
- **Configuration**: Environment variables via `.envrc` (never hardcoded)
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)

### Deployment Process

1. Automated installation via `scripts/install.sh` (idempotent, no manual steps)
2. Service registered with systemd and enabled on boot
3. Health validation: Camera detection, service startup, endpoint reachability
4. Logging configured: Local file rotation + remote shipping if network available
5. Rollback capability: Previous version retained for quick revert

## Development Workflow

### Testing Requirements

- **Unit tests**: OPTIONAL unless dealing with critical algorithms (detection logic, security functions)
- **Integration tests**: REQUIRED for camera interaction, network failure scenarios, storage limits
- **Field validation**: Manual testing on target hardware (Pi Zero 2W) before production release

### Code Review Gates

All changes MUST pass:

1. Resource usage validation (memory profiling, CPU profiling on Pi Zero 2W)
2. Security review (credential handling, authentication, input validation)
3. Offline operation verification (simulate network unavailability)
4. Log quality check (structured, actionable, not noisy)

### Complexity Justification

Any feature that violates resource constraints (Principle II) or adds external dependencies MUST document:

- Why the complexity is necessary (user value, regulatory requirement, etc.)
- What simpler alternatives were considered and why they were insufficient
- Mitigation plan for resource impact (optimization strategy, hardware upgrade path)

## Governance

### Amendment Process

1. Propose change with rationale (why current constitution blocks needed work)
2. Update constitution version following semantic versioning:
   - **MAJOR**: Remove/redefine existing principles (breaking change)
   - **MINOR**: Add new principles or expand guidance
   - **PATCH**: Clarifications, typos, non-semantic fixes
3. Update all dependent templates (plan, spec, tasks) to reflect new constraints
4. Document in Sync Impact Report at top of this file

### Compliance Review

- Constitution compliance is checked during `/speckit.plan` (Constitution Check section)
- Any violations MUST be explicitly justified in the Complexity Tracking table
- Repeated violations signal the need for constitution amendment

### Living Document

This constitution is a living document. When multiple features require the same exception, that signals a principle should be amended rather than repeatedly justified.

**Version**: 1.0.0 | **Ratified**: 2026-01-27 | **Last Amended**: 2026-01-27
