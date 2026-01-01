# libcleona_net

Direct-syscall UDP send-path shim. See `Cleona_Chat_Architecture_v3_0.md` §4.5.2
and §20.3a for the architectural rationale.

## Why this is here

Dart's `RawDatagramSocket.send()` on Windows silently drops roughly 89 % of
sustained UDP sends at ~500 pps during the LAN-Discovery subnet-scan phase.
`pktmon` counters confirm the dropped sends never reach the Win-TCPIP layer —
the defect lives inside Dart's IOCP-based UDP send routine, below where any
Dart-level workaround can reach. PowerShell's `.NET UdpClient` at identical
load shows zero drops because it issues `WSASendTo` synchronously without IOCP
queueing. This shim adopts the `.NET UdpClient` strategy.

The shim is also built on Linux so the Cleona source has a single send-path
code-path across both desktop platforms.

## Public API

See `include/cleona_net.h`. Four functions:

* `cleona_udp_open(local_port, reuse_addr, broadcast_enable)` — open + bind
* `cleona_udp_set_buffers(s, rcv_bytes, snd_bytes)` — `SO_RCVBUF` / `SO_SNDBUF`
* `cleona_udp_send(s, dest_ip, dest_port, data, len)` — synchronous send, returns bytes-sent or `-errno`
* `cleona_udp_close(s)` — close + free

Plus `cleona_net_version()` for diagnostics.

## Build — Linux

```
cd native/cleona_net
cmake -B build -S .
cmake --build build --config Release -j$(nproc)
# Output: build/libcleona_net.so
```

The Flutter Linux release bundle build script copies `libcleona_net.so` next to
`libcleona_audio.so`. See `docs/PUBLISHING.md` for the release-bundle assembly
step.

## Build — Windows

Requires CMake + Visual Studio Build Tools (or full Visual Studio) with C
workload. From a Developer Command Prompt:

```
cd native\cleona_net
cmake -B build -S . -A x64
cmake --build build --config Release
REM Output: build\Release\cleona_net.dll
```

The Cleona Windows release build expects `cleona_net.dll` to sit next to
`cleona-daemon.exe` in `build\windows\x64\runner\Release\`. The DLL has no
external dependencies beyond `ws2_32.dll` (a Windows-bundled system library).

## Phase-1 platform scope

Only Linux x86_64 and Windows x86_64 desktop. Android, iOS, and macOS continue
to use Dart's `RawDatagramSocket` directly. The C source compiles cleanly on
all POSIX targets if Phase 2 ever extends the platform set; for now the build
script does not attempt cross-compilation.
