/*
 * cleona_net implementation.
 *
 * Cross-platform single C file:
 *   - POSIX path (Linux, macOS, Android): plain sendto() on a BSD socket.
 *   - Windows path: WSASendTo() on a WinSock2 socket. WSAStartup is reference-
 *     counted across all open calls.
 *
 * The implementations diverge only in the syscall calls themselves; the data
 * model (struct cleona_udp_socket) is identical.
 */

#include "../include/cleona_net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
  #include <winsock2.h>
  #include <ws2tcpip.h>
  /* Link automatically against Ws2_32.lib when consumed by MSVC */
  #pragma comment(lib, "Ws2_32.lib")
  typedef SOCKET cleona_native_socket_t;
  #define CLEONA_INVALID_SOCKET INVALID_SOCKET
  #define CLEONA_SOCKET_ERROR   SOCKET_ERROR
  #define CLEONA_CLOSE(s)       closesocket(s)
  #define CLEONA_LAST_ERROR()   WSAGetLastError()
#else
  #include <sys/socket.h>
  #include <arpa/inet.h>
  #include <netinet/in.h>
  #include <unistd.h>
  #include <errno.h>
  typedef int cleona_native_socket_t;
  #define CLEONA_INVALID_SOCKET (-1)
  #define CLEONA_SOCKET_ERROR   (-1)
  #define CLEONA_CLOSE(s)       close(s)
  #define CLEONA_LAST_ERROR()   errno
#endif

struct cleona_udp_socket {
  cleona_native_socket_t fd;
};

#define CLEONA_NET_VERSION_STR "cleona_net 1.1.0 (non-blocking WSASendTo)"

#if defined(_WIN32)
/* WSAStartup / WSACleanup are global to the process; the first call to
 * cleona_udp_open initialises and the LAST cleona_udp_close cleans up. We use
 * a simple ref-count protected by an atomic-via-Interlocked counter. */
static volatile LONG g_wsa_refcount = 0;

static int cleona_wsa_init_once(void) {
  LONG before = InterlockedIncrement(&g_wsa_refcount);
  if (before == 1) {
    WSADATA wsa;
    int rc = WSAStartup(MAKEWORD(2, 2), &wsa);
    if (rc != 0) {
      InterlockedDecrement(&g_wsa_refcount);
      return rc;
    }
  }
  return 0;
}

static void cleona_wsa_cleanup_one(void) {
  LONG after = InterlockedDecrement(&g_wsa_refcount);
  if (after == 0) {
    WSACleanup();
  }
}
#endif

CLEONA_NET_EXPORT const char* cleona_net_version(void) {
  return CLEONA_NET_VERSION_STR;
}

CLEONA_NET_EXPORT cleona_udp_socket_t* cleona_udp_open(
    uint16_t local_port,
    int reuse_addr,
    int broadcast_enable) {

#if defined(_WIN32)
  if (cleona_wsa_init_once() != 0) {
    return NULL;
  }
#endif

  /* SOCK_CLOEXEC: prevent the fd from being inherited by child processes
   * (e.g. "ip monitor address" spawned by network_change_handler). If
   * inherited, the subprocess would hold an extra recv-buffer reference,
   * and SO_REUSEPORT's kernel hash could deliver datagrams to the subprocess
   * instead of the Dart listener — even after we move to localPort=0, defence-
   * in-depth. POSIX-only; Windows uses the SECURITY_ATTRIBUTES path for
   * HANDLE inheritance and that is controlled at CreateProcess time. */
#if defined(_WIN32)
  cleona_native_socket_t fd = socket(AF_INET, SOCK_DGRAM, 0);
#else
  cleona_native_socket_t fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
#endif
  if (fd == CLEONA_INVALID_SOCKET) {
#if defined(_WIN32)
    cleona_wsa_cleanup_one();
#endif
    return NULL;
  }

  /* SO_REUSEADDR — lets us coexist with Dart's listening socket on same port */
  if (reuse_addr) {
    int yes = 1;
    /* On Linux, SO_REUSEADDR for UDP is benign; on Windows, it's required for
     * the dual-bind pattern (Dart socket + our shim socket on same port). */
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (const char*)&yes, sizeof(yes));
  }

  /* SO_BROADCAST — required to send to 255.255.255.255 or x.x.x.255 */
  if (broadcast_enable) {
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, (const char*)&yes, sizeof(yes));
  }

  /* Bind to ANY:port (0 = ephemeral). */
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(local_port);
  if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) == CLEONA_SOCKET_ERROR) {
    CLEONA_CLOSE(fd);
#if defined(_WIN32)
    cleona_wsa_cleanup_one();
#endif
    return NULL;
  }

  cleona_udp_socket_t* s = (cleona_udp_socket_t*)malloc(sizeof(cleona_udp_socket_t));
  if (!s) {
    CLEONA_CLOSE(fd);
#if defined(_WIN32)
    cleona_wsa_cleanup_one();
#endif
    return NULL;
  }
  s->fd = fd;

#if defined(_WIN32)
  /* Non-blocking mode: WSASendTo returns WSAEWOULDBLOCK immediately instead
   * of blocking the calling thread when the kernel send-buffer is full.
   * Without this, a burst of 30+ FFI calls from the Dart main isolate during
   * onNetworkChanged can block long enough to trip the Dart VM's stack-guard
   * (GetStackPointerForStackBounds failed → VM crash). */
  {
    u_long nonblocking = 1;
    ioctlsocket(fd, FIONBIO, &nonblocking);
  }
#endif

  return s;
}

CLEONA_NET_EXPORT int cleona_udp_set_buffers(
    cleona_udp_socket_t* s,
    int rcv_bytes,
    int snd_bytes) {
  if (!s) return -1;
  if (rcv_bytes > 0) {
    if (setsockopt(s->fd, SOL_SOCKET, SO_RCVBUF, (const char*)&rcv_bytes, sizeof(rcv_bytes))
        == CLEONA_SOCKET_ERROR) {
      return -1;
    }
  }
  if (snd_bytes > 0) {
    if (setsockopt(s->fd, SOL_SOCKET, SO_SNDBUF, (const char*)&snd_bytes, sizeof(snd_bytes))
        == CLEONA_SOCKET_ERROR) {
      return -1;
    }
  }
  return 0;
}

CLEONA_NET_EXPORT int cleona_udp_send(
    cleona_udp_socket_t* s,
    const char* dest_ip,
    uint16_t dest_port,
    const uint8_t* data,
    int len) {
  if (!s || !dest_ip || !data || len <= 0) {
    return -1;
  }
  struct sockaddr_in dst;
  memset(&dst, 0, sizeof(dst));
  dst.sin_family = AF_INET;
  dst.sin_port = htons(dest_port);
  if (inet_pton(AF_INET, dest_ip, &dst.sin_addr) != 1) {
    return -2;
  }

#if defined(_WIN32)
  /* WSASendTo on a non-blocking socket (FIONBIO). Returns immediately with
   * WSAEWOULDBLOCK when the kernel send-buffer is full instead of blocking
   * the Dart main-isolate thread (which trips GetStackPointerForStackBounds
   * on rapid FFI re-entry). Retry up to 3× with 1ms Sleep — caps worst-case
   * FFI blocking at 3ms per datagram vs. unbounded on a blocking socket. */
  WSABUF buf;
  buf.buf = (CHAR*)data;
  buf.len = (ULONG)len;
  DWORD bytes_sent = 0;
  int rc = WSASendTo(s->fd, &buf, 1, &bytes_sent, 0,
                     (struct sockaddr*)&dst, sizeof(dst), NULL, NULL);
  if (rc != CLEONA_SOCKET_ERROR) {
    return (int)bytes_sent;
  }
  int err = CLEONA_LAST_ERROR();
  if (err != WSAEWOULDBLOCK) {
    return -err;
  }
  for (int retry = 0; retry < 3; retry++) {
    Sleep(1);
    bytes_sent = 0;
    rc = WSASendTo(s->fd, &buf, 1, &bytes_sent, 0,
                   (struct sockaddr*)&dst, sizeof(dst), NULL, NULL);
    if (rc != CLEONA_SOCKET_ERROR) {
      return (int)bytes_sent;
    }
    err = CLEONA_LAST_ERROR();
    if (err != WSAEWOULDBLOCK) {
      return -err;
    }
  }
  return -WSAEWOULDBLOCK;
#else
  /* POSIX sendto. Linux returns the byte count, or -1 with errno on failure.
   * For UDP datagrams under SO_SNDBUF the kernel never returns partial; either
   * the full datagram is queued or sendto returns -1 with EAGAIN/EWOULDBLOCK
   * (only in non-blocking mode — we use blocking sockets). */
  ssize_t n = sendto(s->fd, data, (size_t)len, 0,
                     (struct sockaddr*)&dst, sizeof(dst));
  if (n < 0) {
    return -errno;
  }
  return (int)n;
#endif
}

CLEONA_NET_EXPORT void cleona_udp_close(cleona_udp_socket_t* s) {
  if (!s) return;
  if (s->fd != CLEONA_INVALID_SOCKET) {
    CLEONA_CLOSE(s->fd);
  }
  free(s);
#if defined(_WIN32)
  cleona_wsa_cleanup_one();
#endif
}

CLEONA_NET_EXPORT int cleona_udp_sendto_fd(
    int fd,
    const char* dest_ip,
    uint16_t dest_port,
    const uint8_t* data,
    int len) {
  if (fd < 0 || !dest_ip || !data || len <= 0) return -1;

  struct sockaddr_in dst;
  memset(&dst, 0, sizeof(dst));
  dst.sin_family = AF_INET;
  dst.sin_port = htons(dest_port);
  if (inet_pton(AF_INET, dest_ip, &dst.sin_addr) != 1) return -2;

#if defined(_WIN32)
  WSABUF buf;
  buf.buf = (CHAR*)data;
  buf.len = (ULONG)len;
  DWORD bytes_sent = 0;
  int rc = WSASendTo((SOCKET)(intptr_t)fd, &buf, 1, &bytes_sent, 0,
                     (struct sockaddr*)&dst, sizeof(dst), NULL, NULL);
  if (rc != SOCKET_ERROR) return (int)bytes_sent;
  return -WSAGetLastError();
#else
  ssize_t n = sendto(fd, data, (size_t)len, 0,
                     (struct sockaddr*)&dst, sizeof(dst));
  if (n < 0) return -errno;
  return (int)n;
#endif
}

#if !defined(_WIN32)
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>

static int _find_udp_fd_by_port(uint16_t local_port, int family) {
  DIR* dir = opendir("/proc/self/fd");
  if (!dir) return -1;

  struct dirent* entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] == '.') continue;
    int fd = atoi(entry->d_name);
    if (fd < 0) continue;

    /* Check socket type */
    int sock_type = 0;
    socklen_t optlen = sizeof(sock_type);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &sock_type, &optlen) != 0) continue;
    if (sock_type != SOCK_DGRAM) continue;

    /* Check address family and bound port */
    struct sockaddr_storage addr;
    socklen_t addrlen = sizeof(addr);
    if (getsockname(fd, (struct sockaddr*)&addr, &addrlen) != 0) continue;

    if (family == AF_INET && addr.ss_family == AF_INET) {
      struct sockaddr_in* a4 = (struct sockaddr_in*)&addr;
      if (ntohs(a4->sin_port) == local_port) {
        closedir(dir);
        return fd;
      }
    } else if (family == AF_INET6 && addr.ss_family == AF_INET6) {
      struct sockaddr_in6* a6 = (struct sockaddr_in6*)&addr;
      if (ntohs(a6->sin6_port) == local_port) {
        closedir(dir);
        return fd;
      }
    }
  }
  closedir(dir);
  return -1;
}
#endif

CLEONA_NET_EXPORT int cleona_find_udp4_fd(uint16_t local_port) {
#if defined(_WIN32)
  (void)local_port;
  return -1;
#else
  return _find_udp_fd_by_port(local_port, AF_INET);
#endif
}

CLEONA_NET_EXPORT int cleona_find_udp6_fd(uint16_t local_port) {
#if defined(_WIN32)
  (void)local_port;
  return -1;
#else
  return _find_udp_fd_by_port(local_port, AF_INET6);
#endif
}
