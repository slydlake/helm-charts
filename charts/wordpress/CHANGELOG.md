# Changelog

All notable changes to this WordPress Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.5] - 2025-09-21

### Enhanced
- **ServiceMonitor Namespace Isolation**: Improved ServiceMonitor configuration with proper `namespaceSelector` implementation
- **Cross-Namespace Monitoring Prevention**: Enhanced namespace-specific monitoring to prevent conflicts between multiple WordPress instances
- **Prometheus Target Stability**: Optimized ServiceMonitor scope restriction to ensure stable Prometheus target discovery

### Technical Improvements
- ServiceMonitor templates now properly respect configured namespace settings for both WordPress and Apache metrics
- Reduced monitoring overhead by limiting ServiceMonitor scope to appropriate namespaces
- Enhanced monitoring reliability in multi-tenant Kubernetes environments

## [0.2.4] - 2025-09-21

### Fixed
- **ServiceMonitor Cross-Namespace Conflicts**: Added `namespaceSelector` to both WordPress and Apache ServiceMonitors to prevent cross-namespace scraping conflicts
- **Prometheus Target Down Alerts**: Fixed issue where multiple ServiceMonitors were scraping the same pods, causing "Target Down" alerts
- **Over-Scraping Prevention**: Limited ServiceMonitor scope to the release namespace, reducing unnecessary load on metrics endpoints

### Changed
- ServiceMonitor templates now include `namespaceSelector.matchNames` to restrict monitoring to the appropriate namespace
- Apache ServiceMonitor respects `metrics.apache.serviceMonitor.namespace` configuration option

## [0.2.3] - 2025-09-18

### Changed
- artifacthub verification metadata

## [0.2.2] - 2025-09-18

### Changed
- sample values, secrets and configmaps moved to separate folder

## [0.2.1] - 2025-09-18

### Changed
- signed the chart with cosign

## [0.2.0] - 2025-09-17

### Added
- added support for custom configmaps for apache and php configurations as well as .htaccess file
- signed the chart with cosign

## [0.1.0] - 2025-09-16

### Added
- initial release