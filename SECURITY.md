# Security policy

SUDOSEND is built to be safe on hostile networks: end-to-end encryption (X25519 + ChaCha20-Poly1305),
verified device identities (Ed25519, 6-digit SAS or QR), SHA-256 on every file, signed delivery receipts,
flood protection and an audit log. The design is documented in [PROTOCOL.md](PROTOCOL.md).

## Reporting a vulnerability

Please **do not open a public issue**. Email **ceo@sudosoc.com** with:

- what is affected (app version, platform, protocol step),
- how to reproduce it,
- the impact you expect.

You will get an answer within a few days. Fixes ship in a new release, and reporters are credited in
the release notes unless they prefer otherwise.

## Supported versions

Only the latest release receives security fixes. The app can check for updates itself
(Settings → About → Check for updates) or run `sudosend update`.
