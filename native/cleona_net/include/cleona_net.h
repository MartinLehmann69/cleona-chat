/*
 * cleona_net — direct-syscall UDP send-path for Cleona.
 *
 * Why this exists:
 *   Dart's RawDatagramSocket.send() on Windows silently drops ~89% of sustained
 *   UDP sends at ~500 pps during LAN-Discovery subnet-scan. pktmon shows the
 *   dropped sends never reach the Win-TCPIP layer; the defect is inside Dart's
 *   IOCP-based UDP send routine, below where any Dart-level workaround can
 *   reach. PowerShell's .NET UdpClient at the same load shows zero drops by
 *   issuing WSASendTo synchronously without IOCP queueing.
 *
 * What this is:
 *   A minimal C shim that exposes blocking UDP open/send/close to Dart via FFI.
 *   POSIX sendto() on Linux/macOS/Android; WinSock2 WSASendTo() on Windows.
 *   No recv (Dart's listen path is unaffected by the bug). No multicast group
 *   management (handled on Dart's listening socket).
 *
 * Architecture: see Cleona_Chat_Architecture_v3_0.md §4.5.2 and §20.3a.
 */

#ifndef CLEONA_NET_H
#define CLEONA_NET_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define CLEONA_NET_EXPORT __declspec(dllexport)
#else
  #define CLEONA_NET_EXPORT __attribute__((visibility("default")))
#endif

/* Opaque handle. NULL on failure. */
typedef struct cleona_udp_socket cleona_udp_socket_t;

/*
 * Open a UDP socket bound to local IPv4 ANY:port.
 * SO_REUSEADDR is set so the socket can coexist with Dart's RawDatagramSocket
 * bound to the same port (the Dart socket owns multicast group membership and
 * receive; this shim only sends).
 *
 * Set port=0 to let the OS pick an ephemeral local port (rare — normally we
 * bind to a well-known discovery port like 41338).
 *
 * Set broadcast_enable to non-zero to enable SO_BROADCAST on the socket.
 *
 * Returns: opaque handle on success, NULL on failure.
 */
CLEONA_NET_EXPORT cleona_udp_socket_t* cleona_udp_open(
    uint16_t local_port,
    int reuse_addr,
    int broadcast_enable);

/*
 * Configure SO_RCVBUF + SO_SNDBUF in bytes. Either value may be 0 to skip that
 * option. Returns 0 on success, -1 on error (does not invalidate the socket).
 */
CLEONA_NET_EXPORT int cleona_udp_set_buffers(
    cleona_udp_socket_t* s,
    int rcv_bytes,
    int snd_bytes);

/*
 * Send one UDP datagram synchronously.
 *   dest_ip   — IPv4 dotted-quad string ("192.168.10.74"), null-terminated
 *   dest_port — destination port
 *   data      — payload bytes
 *   len       — payload length (must fit one UDP datagram, ≤ 1472 bytes for safe MTU)
 *
 * Returns: number of bytes sent (== len on success), or a negative errno-style
 * code on failure. Windows: blocks until WSASendTo returns. POSIX: blocks until
 * sendto() returns; on a properly-sized SO_SNDBUF this almost never blocks for
 * the small datagrams Cleona sends (≤ 1200 bytes).
 *
 * The function does NOT validate the destination address beyond what the kernel
 * does (no ARP pre-resolution, no ICMP-feedback caching). Callers above the FFI
 * boundary are responsible for any rate-limiting or pacing.
 */
CLEONA_NET_EXPORT int cleona_udp_send(
    cleona_udp_socket_t* s,
    const char* dest_ip,
    uint16_t dest_port,
    const uint8_t* data,
    int len);

/*
 * Close the socket and release the handle. Safe to call with NULL.
 */
CLEONA_NET_EXPORT void cleona_udp_close(cleona_udp_socket_t* s);

/*
 * Send on an EXISTING file descriptor (not managed by this library).
 * Used on Android/iOS where Dart's RawDatagramSocket owns the fd and we
 * just need native sendto() for errno visibility.
 *
 * Returns: bytes sent on success, or negative errno on failure.
 * Does NOT close or modify the fd in any way.
 */
CLEONA_NET_EXPORT int cleona_udp_sendto_fd(
    int fd,
    const char* dest_ip,
    uint16_t dest_port,
    const uint8_t* data,
    int len);

/*
 * Find an open UDP4 socket fd bound to [local_port] in this process.
 * Scans /proc/self/fd + getsockname(). POSIX-only (Linux/Android).
 *
 * Returns: the fd (>= 0) on success, -1 if not found.
 */
CLEONA_NET_EXPORT int cleona_find_udp4_fd(uint16_t local_port);

/*
 * Find an open UDP6 socket fd bound to [local_port] in this process.
 * Returns: the fd (>= 0) on success, -1 if not found.
 */
CLEONA_NET_EXPORT int cleona_find_udp6_fd(uint16_t local_port);

/*
 * Version string for diagnostics.
 */
CLEONA_NET_EXPORT const char* cleona_net_version(void);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_NET_H */
