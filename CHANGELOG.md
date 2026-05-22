# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][],
and this project adheres to [Semantic Versioning][].

<!--
## Unreleased

### Added
### Changed
### Removed
-->

## [0.2.3][] - 2026-05-22

### Fixed

* Set `*_temp_path` paths for http stats page.

[0.2.3]: https://github.com/WoozyMasta/nginx-restream/compare/0.2.2...0.2.3

## [0.2.2][] - 2026-05-22

### Changed

* The nginx-rtmp-module version has been updated to 1.3.0,
  which adds support for the new `dynamic_exec_arg` directive
  for transcoding streams on a per-destination basis.

[0.2.2]: https://github.com/WoozyMasta/nginx-restream/compare/0.2.1...0.2.2

## [0.2.1][] - 2026-05-21

### Fixed

* Restored functionality from a lost stats.conf file in the `slim` image.

[0.2.1]: https://github.com/WoozyMasta/nginx-restream/compare/0.2.0...0.2.1

## [0.2.0][] - 2026-05-21

### Added

* Standard `latest` image ships a statically built ffmpeg
  (x264, AAC, RTMP/RTMPS protocols, scale/fps/aresample filters)
  for in-nginx transcoding via `exec`

[0.2.0]: https://github.com/WoozyMasta/nginx-restream/compare/0.1.0...0.2.0

## [0.1.0][] - 2026-05-21

### Added

* First public release

[0.1.0]: https://github.com/WoozyMasta/nginx-restream/tree/0.1.0

<!--links-->
[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/2.0.0.html
