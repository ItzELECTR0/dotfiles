#define _GNU_SOURCE
#include <errno.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define MAX_REQUEST 65536

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *kb_manager;
static struct zwlr_virtual_pointer_manager_v1 *ptr_manager;
static struct zwp_virtual_keyboard_v1 *kb;
static struct zwlr_virtual_pointer_v1 *ptr;
static struct xkb_keymap *keymap;
static uint32_t width, height;
static useconds_t key_delay_us = 2000;

struct keypos {
    xkb_keycode_t code;
    xkb_layout_index_t layout;
    xkb_mod_mask_t mods;
};

static void global_add(void *data, struct wl_registry *reg, uint32_t name, const char *iface,
                       uint32_t version) {
    (void)data;
    (void)version;
    if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
    else if (!strcmp(iface, zwp_virtual_keyboard_manager_v1_interface.name))
        kb_manager = wl_registry_bind(reg, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
        ptr_manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data;
    (void)reg;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {global_add, global_remove};

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static const char *socket_path(void) {
    static char path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    const char *dir = getenv("XDG_RUNTIME_DIR");
    snprintf(path, sizeof(path), "%s/agent-input.sock", dir ? dir : "/tmp");
    return path;
}

static int write_all(int fd, const char *buf, size_t len) {
    while (len > 0) {
        ssize_t n = write(fd, buf, len);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        buf += n;
        len -= n;
    }
    return 0;
}

static int upload_keymap(void) {
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    if (!text)
        return -1;
    size_t size = strlen(text) + 1;
    int fd = memfd_create("agent-input-keymap", MFD_CLOEXEC);
    int ok = fd >= 0 && write_all(fd, text, size) == 0;
    free(text);
    if (ok)
        zwp_virtual_keyboard_v1_keymap(kb, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    if (fd >= 0)
        close(fd);
    return ok ? 0 : -1;
}

static int find_keysym(xkb_keysym_t sym, struct keypos *out) {
    xkb_layout_index_t layouts = xkb_keymap_num_layouts(keymap);
    xkb_keycode_t min = xkb_keymap_min_keycode(keymap), max = xkb_keymap_max_keycode(keymap);
    for (xkb_layout_index_t layout = 0; layout < layouts; layout++) {
        for (xkb_keycode_t code = min; code <= max; code++) {
            if (layout >= xkb_keymap_num_layouts_for_key(keymap, code))
                continue;
            xkb_level_index_t levels = xkb_keymap_num_levels_for_key(keymap, code, layout);
            for (xkb_level_index_t level = 0; level < levels; level++) {
                const xkb_keysym_t *syms;
                if (xkb_keymap_key_get_syms_by_level(keymap, code, layout, level, &syms) != 1 ||
                    syms[0] != sym)
                    continue;
                xkb_mod_mask_t masks[4];
                if (xkb_keymap_key_get_mods_for_level(keymap, code, layout, level, masks, 4) == 0)
                    continue;
                *out = (struct keypos){code, layout, masks[0]};
                return 0;
            }
        }
    }
    return -1;
}

static void set_mods(xkb_mod_mask_t mods, xkb_layout_index_t layout) {
    zwp_virtual_keyboard_v1_modifiers(kb, mods, 0, 0, layout);
}

static void tap(const struct keypos *key, xkb_mod_mask_t extra) {
    set_mods(key->mods | extra, key->layout);
    zwp_virtual_keyboard_v1_key(kb, now_ms(), key->code - 8, WL_KEYBOARD_KEY_STATE_PRESSED);
    zwp_virtual_keyboard_v1_key(kb, now_ms(), key->code - 8, WL_KEYBOARD_KEY_STATE_RELEASED);
    set_mods(0, 0);
    wl_display_flush(display);
    usleep(key_delay_us);
}

static int next_codepoint(const char **s, uint32_t *cp) {
    const unsigned char *p = (const unsigned char *)*s;
    int len = p[0] < 0x80 ? 1 : (p[0] >> 5) == 6 ? 2 : (p[0] >> 4) == 14 ? 3 : (p[0] >> 3) == 30 ? 4 : 0;
    if (!len)
        return -1;
    *cp = len == 1 ? p[0] : p[0] & (0x7f >> len);
    for (int i = 1; i < len; i++) {
        if ((p[i] & 0xc0) != 0x80)
            return -1;
        *cp = (*cp << 6) | (p[i] & 0x3f);
    }
    *s += len;
    return 0;
}

static xkb_keysym_t codepoint_keysym(uint32_t cp) {
    if (cp == '\n')
        return XKB_KEY_Return;
    if (cp == '\t')
        return XKB_KEY_Tab;
    return xkb_utf32_to_keysym(cp);
}

static int cmd_type(const char *text, char *err, size_t errlen) {
    for (const char *s = text; *s;) {
        uint32_t cp;
        struct keypos key;
        if (next_codepoint(&s, &cp) < 0) {
            snprintf(err, errlen, "invalid UTF-8");
            return -1;
        }
        if (find_keysym(codepoint_keysym(cp), &key) < 0) {
            snprintf(err, errlen, "no key produces U+%04X", cp);
            return -1;
        }
    }
    for (const char *s = text; *s;) {
        uint32_t cp;
        struct keypos key;
        next_codepoint(&s, &cp);
        find_keysym(codepoint_keysym(cp), &key);
        tap(&key, 0);
    }
    return 0;
}

static xkb_mod_mask_t modifier_mask(const char *name) {
    static const struct {
        const char *alias, *mod;
    } mods[] = {{"ctrl", XKB_MOD_NAME_CTRL},  {"control", XKB_MOD_NAME_CTRL}, {"shift", XKB_MOD_NAME_SHIFT},
                {"alt", XKB_MOD_NAME_ALT},    {"super", XKB_MOD_NAME_LOGO},   {"logo", XKB_MOD_NAME_LOGO},
                {"altgr", "Mod5"}};
    for (size_t i = 0; i < sizeof(mods) / sizeof(mods[0]); i++) {
        if (strcasecmp(name, mods[i].alias))
            continue;
        xkb_mod_index_t idx = xkb_keymap_mod_get_index(keymap, mods[i].mod);
        return idx == XKB_MOD_INVALID ? 0 : 1u << idx;
    }
    return 0;
}

// Each space-separated combo is modifiers joined by '+' and a keysym name last, e.g. ctrl+shift+t.
static int cmd_key(char *combos, char *err, size_t errlen) {
    for (char *save = NULL, *combo = strtok_r(combos, " ", &save); combo; combo = strtok_r(NULL, " ", &save)) {
        xkb_mod_mask_t mask = 0;
        char *name = combo;
        for (char *plus; (plus = strchr(name, '+')) && plus[1];) {
            *plus = '\0';
            xkb_mod_mask_t m = modifier_mask(name);
            if (!m) {
                snprintf(err, errlen, "unknown modifier '%s'", name);
                return -1;
            }
            mask |= m;
            name = plus + 1;
        }
        xkb_keysym_t sym = xkb_keysym_from_name(name, XKB_KEYSYM_NO_FLAGS);
        if (sym == XKB_KEY_NoSymbol)
            sym = xkb_keysym_from_name(name, XKB_KEYSYM_CASE_INSENSITIVE);
        struct keypos key;
        if (sym == XKB_KEY_NoSymbol || find_keysym(sym, &key) < 0) {
            snprintf(err, errlen, "no key for '%s'", name);
            return -1;
        }
        tap(&key, mask);
    }
    return 0;
}

static int parse_button(const char *name, uint32_t *button) {
    static const struct {
        const char *name;
        uint32_t code;
    } buttons[] = {{"left", BTN_LEFT}, {"right", BTN_RIGHT}, {"middle", BTN_MIDDLE},
                   {"back", BTN_SIDE}, {"forward", BTN_EXTRA}};
    if (!name || !*name) {
        *button = BTN_LEFT;
        return 0;
    }
    for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++) {
        if (!strcasecmp(name, buttons[i].name)) {
            *button = buttons[i].code;
            return 0;
        }
    }
    return -1;
}

static void button(uint32_t code, enum wl_pointer_button_state state) {
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), code, state);
    zwlr_virtual_pointer_v1_frame(ptr);
}

static void scroll(enum wl_pointer_axis axis, int steps) {
    uint32_t t = now_ms();
    zwlr_virtual_pointer_v1_axis_source(ptr, WL_POINTER_AXIS_SOURCE_WHEEL);
    zwlr_virtual_pointer_v1_axis_discrete(ptr, t, axis, wl_fixed_from_int(15 * steps), steps);
    zwlr_virtual_pointer_v1_frame(ptr);
}

static int handle(char *req, char *err, size_t errlen) {
    char *arg = strchr(req, ' ');
    if (arg)
        *arg++ = '\0';
    else
        arg = req + strlen(req);

    if (!strcmp(req, "type"))
        return cmd_type(arg, err, errlen);
    if (!strcmp(req, "key"))
        return cmd_key(arg, err, errlen);

    double x, y;
    uint32_t code;
    int steps;
    if (!strcmp(req, "move") && sscanf(arg, "%lf %lf", &x, &y) == 2) {
        if (x < 0 || y < 0 || x > width || y > height) {
            snprintf(err, errlen, "%g,%g is outside %ux%u", x, y, width, height);
            return -1;
        }
        zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), x, y, width, height);
        zwlr_virtual_pointer_v1_frame(ptr);
        return 0;
    }
    if (!strcmp(req, "rel") && sscanf(arg, "%lf %lf", &x, &y) == 2) {
        zwlr_virtual_pointer_v1_motion(ptr, now_ms(), wl_fixed_from_double(x), wl_fixed_from_double(y));
        zwlr_virtual_pointer_v1_frame(ptr);
        return 0;
    }
    if (!strcmp(req, "click") || !strcmp(req, "down") || !strcmp(req, "up")) {
        if (parse_button(arg, &code) < 0) {
            snprintf(err, errlen, "unknown button '%s'", arg);
            return -1;
        }
        if (strcmp(req, "up"))
            button(code, WL_POINTER_BUTTON_STATE_PRESSED);
        if (strcmp(req, "down"))
            button(code, WL_POINTER_BUTTON_STATE_RELEASED);
        return 0;
    }
    if ((!strcmp(req, "scroll") || !strcmp(req, "hscroll")) && sscanf(arg, "%d", &steps) == 1) {
        scroll(req[0] == 'h' ? WL_POINTER_AXIS_HORIZONTAL_SCROLL : WL_POINTER_AXIS_VERTICAL_SCROLL, steps);
        return 0;
    }
    snprintf(err, errlen, "usage: type TEXT | key COMBO... | move X Y | rel DX DY | "
                          "click|down|up [BUTTON] | scroll|hscroll STEPS");
    return -1;
}

static void serve_client(int client) {
    static char req[MAX_REQUEST + 1];
    size_t len = 0;
    struct timeval timeout = {.tv_sec = 2};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    for (ssize_t n; len < MAX_REQUEST && (n = read(client, req + len, MAX_REQUEST - len)) > 0;)
        len += n;
    req[len] = '\0';

    char err[256] = "";
    int rc = handle(req, err, sizeof(err));
    wl_display_roundtrip(display);
    char reply[300];
    snprintf(reply, sizeof(reply), rc == 0 ? "ok\n" : "error: %s\n", err);
    write_all(client, reply, strlen(reply));
}

static int serve(const char *size) {
    if (!size || sscanf(size, "%ux%u", &width, &height) != 2 || !width || !height) {
        fprintf(stderr, "usage: agent-input serve WIDTHxHEIGHT\n");
        return 2;
    }
    const char *delay = getenv("AGENT_INPUT_KEY_DELAY_MS");
    if (delay)
        key_delay_us = atoi(delay) * 1000;

    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "agent-input: cannot connect to the Wayland display\n");
        return 1;
    }
    wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !kb_manager || !ptr_manager) {
        fprintf(stderr, "agent-input: compositor lacks a seat or virtual input support\n");
        return 1;
    }

    // Layout comes from XKB_DEFAULT_LAYOUT and friends, which xkbcommon reads itself.
    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = {0};
    keymap = ctx ? xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
    if (!keymap) {
        fprintf(stderr, "agent-input: cannot compile keymap\n");
        return 1;
    }

    kb = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(kb_manager, seat);
    ptr = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(ptr_manager, seat);
    if (upload_keymap() < 0) {
        fprintf(stderr, "agent-input: cannot upload keymap\n");
        return 1;
    }
    wl_display_roundtrip(display);

    const char *path = socket_path();
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    unlink(path);
    umask(077);
    if (listener < 0 || bind(listener, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(listener, 4) < 0) {
        perror("agent-input: socket");
        return 1;
    }

    struct pollfd fds[2] = {{.fd = wl_display_get_fd(display), .events = POLLIN},
                            {.fd = listener, .events = POLLIN}};
    for (;;) {
        wl_display_dispatch_pending(display);
        wl_display_flush(display);
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (fds[0].revents & (POLLERR | POLLHUP))
            break;
        if ((fds[0].revents & POLLIN) && wl_display_dispatch(display) < 0)
            break;
        if (fds[1].revents & POLLIN) {
            int client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
            if (client >= 0) {
                serve_client(client);
                close(client);
            }
        }
    }
    unlink(path);
    return 0;
}

static int send_request(int argc, char **argv) {
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    strncpy(addr.sun_path, socket_path(), sizeof(addr.sun_path) - 1);
    if (fd < 0 || connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "agent-input: no server at %s\n", addr.sun_path);
        return 1;
    }
    for (int i = 1; i < argc; i++) {
        if ((i > 1 && write_all(fd, " ", 1) < 0) || write_all(fd, argv[i], strlen(argv[i])) < 0) {
            perror("agent-input: write");
            return 1;
        }
    }
    shutdown(fd, SHUT_WR);

    char reply[512];
    ssize_t n = read(fd, reply, sizeof(reply) - 1);
    if (n <= 0) {
        fprintf(stderr, "agent-input: no reply\n");
        return 1;
    }
    reply[n] = '\0';
    if (!strncmp(reply, "ok", 2))
        return 0;
    fputs(reply, stderr);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: agent-input serve WIDTHxHEIGHT | agent-input COMMAND [ARGS...]\n");
        return 2;
    }
    if (!strcmp(argv[1], "serve"))
        return serve(argc > 2 ? argv[2] : NULL);
    return send_request(argc, argv);
}
