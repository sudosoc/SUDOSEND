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

`t` ∈ `announce | reply | bye`. A newcomer gets a unicast `reply`. Peers unseen for
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
| 2 | OFFER | `{"files":[{"name":…,"size":…}]}` |
| 3 | ACCEPT | — |
| 4 | DECLINE | — |
| 5 | FILE_START | `{"i":0,"name":…,"size":…}` |
| 6 | DATA | raw bytes (≤ 256 KiB) |
| 7 | FILE_END | `{"i":0,"sha256":b64}` |
| 8 | DONE | — |
| 9 | RESULT | `{"ok":true,"verified":n}` |
| 10 | CANCEL | — |
| 11 | ERROR | UTF-8 reason |

## 5. Session flow

```
C: OFFER                    S: shows SAS + files → user accepts → ACCEPT
C: FILE_START, DATA…, FILE_END   (per file, in order)
C: DONE                     S: RESULT
```

Receiver rules: file names are reduced to a safe basename (no traversal, no reserved
Windows names); bytes beyond the declared size abort the session; data is written to a
hidden `.name.sudosend-part` file and only renamed after the SHA-256 matches; any
protocol violation closes the connection and deletes the partial file.

## Known limitations (v1)

- Discovery metadata (device name, fingerprint) is visible on the LAN.
- No resume yet — planned for v2 via per-chunk offsets.
- File sizes and names are visible to the receiver before acceptance (by design).
