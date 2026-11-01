# Wraith Protocol v1

The wire protocol behind SUDOSEND. Peer-to-peer, LAN-only, no servers, no accounts.

## Goals

| Goal | Mechanism |
|---|---|
| Confidentiality | X25519 ephemeral ECDH → HKDF-SHA256 → ChaCha20-Poly1305 |
| Forward secrecy | Fresh ephemeral X25519 keys for every connection |
| Integrity of every frame | Poly1305 tag + implicit 64-bit counter nonce (no reorder / replay / splice) |
| Integrity of every file | SHA-256 over the plaintext, checked before the file is kept |
| Authentication | Long-term Ed25519 identity signs the handshake transcript |
| MITM resistance (first contact) | 6-digit SAS + hash commitment (no key grinding) |
| MITM resistance (later) | Trusted fingerprint store (TOFU after a verified SAS) |
| Receiver safety | Name sanitisation, declared-size enforcement, temp files, explicit consent |
| Flood resistance | Per-IP and global connection limits, one prompt per address, block list |
| Key at rest | Identity seed sealed by Android Keystore / Windows DPAPI; owner-only file elsewhere |
| Out-of-band pairing | QR link carries the receiver fingerprint + one-time token |

## Identity

Each device generates an Ed25519 key pair on first launch and stores it locally
(`identity.json`, `chmod 600` on Linux). Its **fingerprint** is the first 128 bits of
`SHA-256(public_key)`, shown as 32 uppercase hex characters.

## 1. Discovery — UDP 47823

JSON datagram, sent every 3 s to multicast `239.255.77.23`, `255.255.255.255`
and each interface's `/24` broadcast address:

```json
{"wraith":1,"t":"announce","id":"<fingerprint>","name":"Seif-Laptop","platform":"linux","port":47824}
```

`t` ∈ `announce | reply | probe | bye`. A newcomer gets a unicast `reply`. `probe` is sent by
passive clients (CLI `send` / `devices`) that want to find receivers without advertising
themselves; receivers answer it with `reply` and do not list the prober. Peers unseen for
10 s are dropped. Announcements are **hints only** — unauthenticated by design. If the
fingerprint proven in the handshake differs from the advertised `id`, the sender aborts.

## 2. Transport — TCP 47824 (falls back to 47825–47833)

Every frame: `u32 big-endian length ‖ payload`. Max encrypted frame: 1 MiB + 64.

## 3. Handshake

`C` = sender (initiator), `S` = receiver.

```
C → S   {"proto":"WRAITH/1","commit": b64(SHA-256(HelloC))}
S → C   HelloS
C → S   HelloC                       S verifies SHA-256(HelloC) == commit
Hello = {"proto":"WRAITH/1","eph":b64(X25519 pub),"id":b64(Ed25519 pub),"name":…,"platform":…}
```

The commitment forces C to fix its ephemeral key before seeing S's, and S to send its
key before seeing C's — so a man-in-the-middle cannot grind keys until both SAS values
collide. Success probability for an active MITM is 10⁻⁶ per attempt.

```
TH    = SHA-256("WRAITH/1 transcript" ‖ u32|HelloC| ‖ HelloC ‖ u32|HelloS| ‖ HelloS)
Z     = X25519(eph_self, eph_peer)          (all-zero output rejected)
k_c2s = HKDF-SHA256(Z, salt=TH, info="WRAITH/1 c2s")
k_s2c = HKDF-SHA256(Z, salt=TH, info="WRAITH/1 s2c")
SAS   = u32(HKDF-SHA256(Z, salt=TH, info="WRAITH/1 sas")[0..4]) mod 10⁶
```

Then, encrypted, both sides send `AUTH = Ed25519_sign(id, "WRAITH/1 auth " ‖ role ‖ TH)`
with role `C` or `S`, and verify the peer's signature with the identity key from its Hello.

## 4. Encrypted frames

```
payload = ChaCha20-Poly1305(key_dir, nonce = 0x00000000 ‖ u64 counter_dir, type ‖ body) ‖ tag
```

| Type | Name | Body |
|---|---|---|
| 1 | AUTH | 64-byte signature |
| 2 | OFFER | `{"files":[{name,size,mtime?}…], "text"?, "pair"?, "clip"?, "ring"?, "chat"?, "sync"?, "previews"?, "speedtest"?, "syncManifest"?, "syncInvite"?}` (§13) |
| 3 | ACCEPT | `{"resume":{"<index>": bytes_already_held}, "caps":["z"]}` |
| 4 | DECLINE | — |
| 5 | FILE_START | `{"i":0,"name":…,"size":…,"offset":…}` |
| 6 | DATA | raw bytes (≤ 256 KiB) |
| 7 | FILE_END | `{"i":0,"sha256":b64}` |
| 8 | DONE | — |
| 9 | RESULT | `{"ok":true,"verified":n,"receipt":"<signed JSON>","sig":b64}` |
| 10 | CANCEL | — |
| 11 | ERROR | UTF-8 reason |
| 12 | DATA_Z | raw-deflate bytes that inflate to ≤ 256 KiB (§13) |

## 5. Folders, text and resume

- **Folders**: `name` is a relative path with `/` separators. The receiver sanitises every
  segment independently and re-checks that the final path is inside its receive folder.
- **Text**: an OFFER with an empty `files` list and a `text` (≤ 64 KiB) carries a message.
  After ACCEPT the sender sends DONE directly.
- **Resume**: partial data lives in `.<name>.<fp8>-<size>.sudosend-part`, keyed by the
  sender's fingerprint and the file size, so only the same device sending the same-sized
  file can resume it. The receiver lists the bytes it already holds in ACCEPT; the sender
  skips them (but still hashes them) and echoes the offset in FILE_START. The final
  SHA-256 always covers the **whole** file, so a corrupted or forged partial is detected
  and deleted. Partials survive dropped connections and are deleted on cancel, integrity
  or protocol failures.

## 6. QR pairing

The receiver shows `sudosend://pair?v=1&n=<name>&fp=<fingerprint>&a=<ip>,<ip>&p=<port>&t=<token>`
as a QR code. `t` is 128 random bits, single use, valid ≤ 10 minutes.

- The **sender** connects to the listed addresses and aborts unless the handshake proves `fp`
  (the QR is an authenticated out-of-band channel for the receiver's key). It then trusts `fp`.
- The sender puts `t` in the OFFER, inside the encrypted channel. The **receiver** compares it
  in constant time with its live tokens; on a match the token is burned, the sender's
  fingerprint is trusted and the transfer is accepted without a prompt.
- An attacker who did not see the screen cannot produce `t`; one who copies the QR still cannot
  impersonate the receiver (no private key for `fp`).

## 7. Signed delivery receipts

At DONE the receiver builds a receipt (JSON: sender and receiver names + fingerprints, UTC
completion time, session transcript hash `TH`, and name / size / SHA-256 of every file, or the
SHA-256 of a text message) and signs `"WRAITH/1 receipt\n" ‖ receipt` with its Ed25519 identity
key. The sender verifies the signature with the key proven in the handshake and checks that the
session hash and every file hash match what it sent; any mismatch fails the transfer.

Exported receipts (`sudosend-receipt/1`) carry the exact signed text, the signature and the
signer's public key, so they can be verified offline by anyone (`sudosend verify`). A receipt
proves that the holder of that device key acknowledged those exact bytes in that session.

## 8. Flood control

A receiver drops connections beyond 8 concurrent sessions, 3 per IP, or 20 new connections per
IP per minute. Only one approval prompt per IP (and 3 overall) can be open at a time; extra
requests are declined. Fingerprints on the user's block list are declined before any prompt.

## 9. Performance

Frames are sealed and opened by an `AeadEngine`: an optimised pure-Dart RFC 8439
implementation (unrolled ChaCha20 rounds, 26-bit-limb Poly1305) run on a pool of worker
isolates. Nonces are assigned when a frame is queued; a sequential write chain keeps frames in
order while several are encrypted in parallel, and the receiver opens up to 6 frames ahead.
The socket is flushed every 1 MiB instead of every frame. Files ≥ 4 MiB are hashed on a
background isolate. CI benchmarks every build on x64 and ARM64.

## 10. Session flow

```
C: OFFER                    S: shows SAS + files → user accepts → ACCEPT
C: FILE_START, DATA…, FILE_END   (per file, in order)
C: DONE                     S: RESULT
```

Receiver rules: file names are reduced to a safe basename (no traversal, no reserved
Windows names); bytes beyond the declared size abort the session; data is written to a
hidden `.name.sudosend-part` file and only renamed after the SHA-256 matches; any
protocol violation closes the connection and deletes the partial file.

## 11. Clipboard sync and browser sharing

- An OFFER with `"clip": true` (text only) is a universal-clipboard push. Apps accept it silently
  only from **trusted** devices with clipboard sync enabled, and decline it without a prompt
  otherwise. It travels over the same encrypted channel as any transfer.
- *Browser sharing* is a separate, opt-in HTTP server (TCP 47840–47849) for devices without the
  app, under `/s/<128-bit token>/`. It is **not** end-to-end encrypted (plain HTTP on the LAN);
  wrong-token probes are rate-limited, uploads are sanitised like normal transfers, and the share
  expires after 30 minutes or when stopped.

## 12. Find my device, outbox, protected links

- `"ring": true` with no files and no text asks the receiver to ring. Apps accept it only from
  trusted devices (and only if the user allows it); anything else is declined without a prompt.
- The outbox and automatic retries are app features: a failed transfer to the same fingerprint
  is simply retried, and the resume mechanism (§5) skips what already arrived.
- Browser links can require a PIN (checked in constant time, rate-limited like token probes; a
  correct PIN sets an HMAC session cookie scoped to the share path) and can stop after a set
  number of downloads.

## 13. Compression, previews, messages, speed test, folder sync (v0.7)

- **Compression.** The receiver lists `"z"` in ACCEPT `caps`. The sender may then send any chunk as
  DATA_Z (raw deflate, level 1) when that shrinks it by ≥ 10 %; extensions that are already
  compressed are skipped and a file stops trying after 3 misses. The receiver inflates with a hard
  output cap of `min(256 KiB, bytes still expected)`, so a decompression bomb is rejected. SHA-256
  is computed over the inflated bytes. Old receivers send no caps and get plain DATA.
- **Previews.** `"previews": {"<file index>": base64 PNG}` — at most 8, each ≤ ~100 KB; invalid
  indexes or oversized entries are dropped. They are inside the encrypted OFFER like everything else.
- **Messages.** `"chat": true` on a text offer marks it as a message for the receiver's thread view.
  It changes nothing on the wire otherwise.
- **Speed test.** An OFFER with no files and `"speedtest": true`. Receivers accept only from trusted
  devices (if allowed), then count DATA bytes until DONE and answer RESULT `{"ok", "bytes", "ms"}`.
  Nothing is written to disk.
- **Folder sync.** Pairs are identified by a random id and bound to a fingerprint on both sides.
  - `"syncInvite": {"id","name"}` asks the user to pick a local folder; ACCEPT/DECLINE is the answer.
  - `"syncManifest": "<id>"` is answered (trusted devices only) with ACCEPT
    `{"manifest": base64(gzip(JSON [{p,s,m}]))}` — relative path, size, mtime in ms. Hidden entries
    are skipped. Unknown id or untrusted device → DECLINE.
  - A push is a normal file OFFER with `"sync": "<id>"` and per-file `mtime`. It is auto-accepted
    only from the bound fingerprint. Files land at their relative path (no renaming); an existing
    file is first moved to `.sudosend-archive/<timestamp>/`, and the received file gets the
    sender's mtime so the next comparison sees them as equal.
  - Each side pushes what the other lacks or has older (> 2 s difference). Deletions are never sent.

## Known limitations

- Discovery metadata (device name, fingerprint) is visible on the LAN — use stealth mode to stop announcing.
- iOS blocks broadcast/multicast for apps without an Apple-granted entitlement: on iPhone use QR or IP.
- File sizes and names are visible to the receiver before acceptance (by design).
- Folder sync is last-writer-wins by modification time: two edits to the same file between rounds
  keep the newer one live and the older one in the archive. Clocks that are badly wrong skew this.
- Where a file system refuses to set modification times, a synced file may be sent back once.
