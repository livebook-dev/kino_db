# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- SQL Server integration ([#65](https://github.com/livebook-dev/kino_db/pull/65))

## [v0.2.2](https://github.com/livebook-dev/kino_db/tree/v0.2.2) (2023-08-31)

### Added

- SSL support for Connection cell ([#60](https://github.com/livebook-dev/kino_db/pull/60))
- Snowflake integration ([#61](https://github.com/livebook-dev/kino_db/pull/61))

### Changed

- Settings as a dynamic header ([#62](https://github.com/livebook-dev/kino_db/pull/62))

### Fixed

- Restores ipv6 config from attrs ([#58](https://github.com/livebook-dev/kino_db/pull/58))

## [v0.2.1](https://github.com/livebook-dev/kino_db/tree/v0.2.1) (2022-12-05)

### Changed

* Relaxed requirement on Kino to `~> 0.7`

### Fixed

* SQL cell error when there is no default connection ([#52](https://github.com/livebook-dev/kino_db/pull/52))

## [v0.2.0](https://github.com/livebook-dev/kino_db/tree/v0.2.0) (2022-10-07)

### Added

- Integration with Livebook secrets for passwords and secret keys ([#32](https://github.com/livebook-dev/kino_db/pull/32) and [#43](https://github.com/livebook-dev/kino_db/pull/43))

### Changed

- Made IPv6 connection an opt-in ([#46](https://github.com/livebook-dev/kino_db/pull/46))

## [v0.1.3](https://github.com/livebook-dev/kino_db/tree/v0.1.3) (2022-07-14)

### Added

- Support AWS Athena new features ([#27](https://github.com/livebook-dev/kino_db/pull/27))
- Support for IPv6 address ([#26](https://github.com/livebook-dev/kino_db/pull/26))

### Fixed

- Scan binding for `Req.Request` connections and Req plugins versions ([#20](https://github.com/livebook-dev/kino_db/pull/20))

## [v0.1.2](https://github.com/livebook-dev/kino_db/tree/v0.1.2) (2022-06-30)

### Added

- Color required inputs and block source code generation when they're empty ([#20](https://github.com/livebook-dev/kino_db/pull/20))
- Support for AWS Athena ([#15](https://github.com/livebook-dev/kino_db/pull/15))
- Support for Google BigQuery ([#7](https://github.com/livebook-dev/kino_db/pull/7), [#18](https://github.com/livebook-dev/kino_db/pull/18) and [#19](https://github.com/livebook-dev/kino_db/pull/19))
- Support for SQLite ([#2](https://github.com/livebook-dev/kino_db/pull/2))
- Warning when there's no available connection ([#11](https://github.com/livebook-dev/kino_db/pull/11))

## [v0.1.1](https://github.com/livebook-dev/kino_db/tree/v0.1.1) (2022-05-03)

### Fixed

- Smart cells source synchronization before evaluation ([#3](https://github.com/livebook-dev/kino_db/pull/3))

## [v0.1.0](https://github.com/livebook-dev/kino_db/tree/v0.1.0) (2022-04-28)

Initial release.
