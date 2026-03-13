# Changelog

All notable changes to linkhut will be documented in this file.

## [Unreleased]

- Add support for setting user preferences (show URLs below titles, show exact dates, timezone and default bookmark privacy)
- Improve relative date display
- Dropped arm64 Docker images (amd64 only for now)
- Account-age quarantine is now configurable and applied to search, popular, and URL timelines (previously only applied to recent view)

## [0.1.2] - 2026-03-12

- Add more MIME types that can be compressed at-rest.
- Introduce concept of subscriptions instead of relying on user types to determine Archiving eligibility
- Add a proper URL history page at `/-:url` (this deprecates the `/-:url/*:tags` that were really not that useful)
- URL matching now treats hostnames as case-insensitive and ignores default ports

## [0.1.1] - 2026-03-10

- Add ban/unban commands and improved error handling to the admin CLI.
- Redesign archive scheduler as queue-filler with domain cooldown
- Add user stats tab and admin archiving dashboard
- Add timeout safety nets for jobs
- Add gzip-at-rest compression for local snapshots

## [0.1.0] - 2026-03-08

Initial tracked release.
