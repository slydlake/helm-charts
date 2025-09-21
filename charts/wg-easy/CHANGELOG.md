# Changelog

## 0.1.17 - 2025-09-21

### Added

- serviceMonitor.namespace property template support
- sample value and secret in separate folder

### Security

- Improved PodSecurity Standards compliance (privileged namespace required)
- Use minimal privileges instead of privileged mode
- Added namespace labels for PodSecurity Standards

## 0.1.16 - 2025-09-18

### Added

- externalIPs in values.yaml

## 0.1.15 - 2025-09-18

### Fixed

- wrong indentation of externalIPs in service

## 0.1.14 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.13 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.12 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.11 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.10 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.9 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.8 - 2025-09-17

### Added

- signed the chart with cosign

## 0.1.7 - 2025-09-16

### Changed

- changed to MIT license

## 0.1.6 - 2025-08-30

### Added

- externalIPs in service type LoadBalancer. Thanks to b4u-mw
- hostNetwork

### Fixed

- service name in ingress. Thanks to b4u-mw
- updateStrategy naming in template

### Changed

- No force of storageClass or existingClaim (by using default class)

## 0.1.5 - 2025-08-25

### Fixed

- values schema required fields

## 0.1.4 - 2025-08-24

### Added

- updateStrategy, Init containers support, sidecar support, dnsPolicy and dnsConfig support

## 0.1.3 - 2025-08-19

### Changed

- Updated values schema required fields

## 0.1.2 - 2025-08-19

### Changed

- Updated values schema required fields

## 0.1.1 - 2025-08-19

### Added

- Added values schema

## 0.1.0 - 2025-08-17

### Added

- Initial release of wg-easy chart.