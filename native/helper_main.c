/*
 * FANcyHelper — Privileged helper daemon for SMC fan control.
 * Runs as root via LaunchDaemon. Listens on a Unix domain socket
 * for commands from the main app.
 *
 * Commands (newline-terminated):
 *   set <fan> <rpm>   — set fan to manual mode + target RPM
 *   auto              — restore all fans to automatic
 *   quit              — stop the helper daemon
 *
 * Responds with "ok" or "error: <msg>"
 */

#include "SMCBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <sys/stat.h>

#define SOCKET_PATH "/tmp/fancy-fan.sock"
#define MAX_CMD 256

static int server_fd = -1;
static volatile int running = 1;

static void cleanup(void) {
    if (server_fd >= 0) close(server_fd);
    unlink(SOCKET_PATH);
    /* Restore auto on exit */
    int n = smc_bridge_read_ui8("FNum");
    if (n < 0) n = 2;
    for (int i = 0; i < n; i++) {
        char k[5];
        snprintf(k, 5, "F%dmd", i);
        smc_bridge_write_ui8(k, 0);
    }
    smc_bridge_close();
}

static void handle_signal(int sig) {
    (void)sig;
    running = 0;
}

static void handle_command(int client_fd, const char *cmd) {
    char resp[128] = "ok\n";

    if (strncmp(cmd, "set ", 4) == 0) {
        int fan = 0;
        float rpm = 0;
        if (sscanf(cmd + 4, "%d %f", &fan, &rpm) == 2) {
            char k[5];
            /* Clamp */
            snprintf(k, 5, "F%dMn", fan);
            float mn = smc_bridge_read_float(k);
            snprintf(k, 5, "F%dMx", fan);
            float mx = smc_bridge_read_float(k);
            if (mn > 0 && rpm < mn) rpm = mn;
            if (mx > 0 && rpm > mx) rpm = mx;

            snprintf(k, 5, "F%dmd", fan);
            if (smc_bridge_write_ui8(k, 1) != 0) {
                snprintf(resp, sizeof(resp), "error: failed to set manual mode\n");
            } else {
                snprintf(k, 5, "F%dTg", fan);
                if (smc_bridge_write_float(k, rpm) != 0) {
                    snprintf(resp, sizeof(resp), "error: failed to set RPM\n");
                }
            }
        } else {
            snprintf(resp, sizeof(resp), "error: usage: set <fan> <rpm>\n");
        }
    } else if (strncmp(cmd, "auto", 4) == 0) {
        int n = smc_bridge_read_ui8("FNum");
        if (n < 0) n = 2;
        for (int i = 0; i < n; i++) {
            char k[5];
            snprintf(k, 5, "F%dmd", i);
            smc_bridge_write_ui8(k, 0);
        }
    } else if (strncmp(cmd, "quit", 4) == 0) {
        running = 0;
    } else {
        snprintf(resp, sizeof(resp), "error: unknown command\n");
    }

    send(client_fd, resp, strlen(resp), 0);
}

int main(void) {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    atexit(cleanup);

    if (smc_bridge_open() != 0) {
        fprintf(stderr, "Failed to open SMC\n");
        return 1;
    }

    /* Create Unix domain socket */
    unlink(SOCKET_PATH);
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        return 1;
    }

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }

    /* Allow all users to connect */
    chmod(SOCKET_PATH, 0666);

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        return 1;
    }

    fprintf(stderr, "FANcyHelper listening on %s\n", SOCKET_PATH);

    while (running) {
        int client = accept(server_fd, NULL, NULL);
        if (client < 0) continue;

        char buf[MAX_CMD] = {0};
        ssize_t n = recv(client, buf, sizeof(buf) - 1, 0);
        if (n > 0) {
            /* Remove trailing newline */
            if (buf[n - 1] == '\n') buf[n - 1] = '\0';
            handle_command(client, buf);
        }
        close(client);
    }

    return 0;
}
