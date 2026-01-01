/*
 * cleona_udp_ios.c — Native UDP sendto() bypass for iOS.
 *
 * Dart's RawDatagramSocket.send() returns 0 on iOS for all destinations
 * (errno 64 EHOSTDOWN / errno 65 EHOSTUNREACH reported asynchronously).
 * This is the same class of bug that led to libcleona_net on Windows.
 *
 * Instead of opening a second socket (which would steal incoming packets
 * on BSD — §4.5.2), we FIND the existing Dart socket's file descriptor
 * by scanning open fds for a UDP socket bound to the expected port, then
 * call sendto() directly on that fd. Same port, same socket, no conflict.
 *
 * Linked statically into the Runner binary; resolved via
 * DynamicLibrary.process() from Dart.
 */

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <unistd.h>

/* Find the file descriptor of a UDP socket bound to the given local port.
 * Returns the fd on success, -1 if not found. Scans fds 3..1023. */
__attribute__((visibility("default"), used))
int cleona_ios_find_udp_fd(int local_port) {
    for (int fd = 3; fd < 1024; fd++) {
        struct sockaddr_in addr;
        socklen_t len = sizeof(addr);
        if (getsockname(fd, (struct sockaddr*)&addr, &len) != 0) continue;
        if (addr.sin_family != AF_INET) continue;
        if (ntohs(addr.sin_port) != (uint16_t)local_port) continue;
        /* Verify it's a DGRAM socket */
        int type = 0;
        socklen_t tlen = sizeof(type);
        if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &tlen) != 0) continue;
        if (type != SOCK_DGRAM) continue;
        return fd;
    }
    return -1;
}

/* Send a UDP datagram via sendto() on the given fd.
 * Returns bytes sent (>0) on success, or -errno on failure. */
__attribute__((visibility("default"), used))
int cleona_ios_sendto(int fd, const char* dest_ip, int dest_port,
                      const void* data, int len) {
    struct sockaddr_in dest;
    memset(&dest, 0, sizeof(dest));
    dest.sin_family = AF_INET;
    dest.sin_port = htons((uint16_t)dest_port);
    if (inet_pton(AF_INET, dest_ip, &dest.sin_addr) != 1) return -22; /* EINVAL */

    ssize_t sent = sendto(fd, data, (size_t)len, 0,
                          (struct sockaddr*)&dest, sizeof(dest));
    if (sent < 0) {
        /* Return -errno so Dart can log the actual error */
        extern int errno;
        return -errno;
    }
    return (int)sent;
}

/* Create a fresh UDP socket for sending only (broadcast + unicast).
 * Used by discovery where Dart's socket fd is unstable on iOS (fd gets
 * recycled between scan and first send → ENOTSOCK/EBADF).
 * Returns the fd (>= 0) on success, or -errno on failure. */
__attribute__((visibility("default"), used))
int cleona_ios_create_send_socket(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        extern int errno;
        return -errno;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, sizeof(yes));
    return fd;
}

/* Peek at the socket's receive buffer without consuming data.
 * Diagnostic: detects data stuck in kernel buffer that Dart's event loop
 * isn't reading (kqueue/CFSocket integration bug).
 * Returns 1 if data is available, 0 on EOF, or -errno (-35 = EAGAIN = empty). */
__attribute__((visibility("default"), used))
int cleona_ios_recv_peek(int fd) {
    char buf[1];
    ssize_t n = recvfrom(fd, buf, 1, MSG_DONTWAIT | MSG_PEEK, NULL, NULL);
    if (n > 0) return 1;
    if (n == 0) return 0;
    extern int errno;
    return -errno;
}
