/* conformance_harness.c — see conformance_harness.h. */

#include "conformance_harness.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    char        id[12];
    ch_status_t status;
    char        title[72];
    char        detail[320];
} ch_result_t;

static ch_result_t g_res[CH_MAX_RESULTS];
static int         g_n;
static int         g_fail;
static int         g_overflow;

typedef struct {
    char key[40];
    char val[160];
    int  is_int;
} ch_kv_t;

static ch_kv_t g_rep[48];
static int     g_rep_n;

static char g_suite[128];
static char g_binding[16];
static char g_library[1024];
static char g_fatal[320];

void ch_begin(const char* suite, const char* binding, const char* library) {
    snprintf(g_suite,   sizeof(g_suite),   "%s", suite   ? suite   : "");
    snprintf(g_binding, sizeof(g_binding), "%s", binding ? binding : "");
    snprintf(g_library, sizeof(g_library), "%s", library ? library : "");
    printf("%s\n", suite);
    printf("binding=%s library=%s\n", g_binding,
           g_library[0] ? g_library : "(linked in)");
    printf("=========================================================================\n");
    fflush(stdout);
}

static void record(const char* id, const char* title, ch_status_t st,
                   const char* fmt, va_list ap) {
    char detail[320];
    if (fmt) {
        vsnprintf(detail, sizeof(detail), fmt, ap);
    } else {
        detail[0] = '\0';
    }

    if (st == CH_FAIL) g_fail++;

    if (g_n < CH_MAX_RESULTS) {
        ch_result_t* r = &g_res[g_n++];
        snprintf(r->id,     sizeof(r->id),     "%s", id);
        snprintf(r->title,  sizeof(r->title),  "%s", title);
        snprintf(r->detail, sizeof(r->detail), "%s", detail);
        r->status = st;
    } else {
        g_overflow = 1;
    }

    printf("%-4s %-5s %-52s %s\n",
           st == CH_PASS ? "PASS" : (st == CH_FAIL ? "FAIL" : "NOTE"),
           id, title, detail);
    fflush(stdout);
}

void ch_check(const char* id, const char* title, int ok, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    record(id, title, ok ? CH_PASS : CH_FAIL, fmt, ap);
    va_end(ap);
}

void ch_note(const char* id, const char* title, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    record(id, title, CH_NOTE, fmt, ap);
    va_end(ap);
}

void ch_section(const char* name) {
    printf("\n-- %s --\n", name);
    fflush(stdout);
}

static void report_put(const char* key, const char* val, int is_int) {
    if (g_rep_n >= (int)(sizeof(g_rep) / sizeof(g_rep[0]))) return;
    snprintf(g_rep[g_rep_n].key, sizeof(g_rep[g_rep_n].key), "%s", key);
    snprintf(g_rep[g_rep_n].val, sizeof(g_rep[g_rep_n].val), "%s", val);
    g_rep[g_rep_n].is_int = is_int;
    g_rep_n++;
}

void ch_report_int(const char* key, int64_t value) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)value);
    report_put(key, buf, 1);
}

void ch_report_str(const char* key, const char* value) {
    report_put(key, value ? value : "", 0);
}

int ch_failures(void) { return g_fail; }

/* Minimal JSON string escaping. The harness controls every string it emits, but
 * a backend-supplied path can contain a backslash on Windows, and an unescaped
 * one would produce a JSON document that a comparison script silently
 * misreads. */
static void json_str(FILE* f, const char* s) {
    fputc('"', f);
    for (; s && *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') { fputc('\\', f); fputc(c, f); }
        else if (c == '\n')        { fputs("\\n", f); }
        else if (c < 0x20)         { fprintf(f, "\\u%04x", c); }
        else                       { fputc((char)c, f); }
    }
    fputc('"', f);
}

static const char* status_name(ch_status_t s) {
    return s == CH_PASS ? "pass" : (s == CH_FAIL ? "fail" : "note");
}

static void write_json(FILE* f, const char* verdict) {
    fputs("{", f);
    fputs("\"suite\":", f);    json_str(f, g_suite);
    fputs(",\"binding\":", f); json_str(f, g_binding);
    fputs(",\"library\":", f); json_str(f, g_library);
    fprintf(f, ",\"checks\":%d,\"failures\":%d", g_n, g_fail);
    fputs(",\"verdict\":", f); json_str(f, verdict);
    if (g_fatal[0]) { fputs(",\"fatal\":", f); json_str(f, g_fatal); }
    if (g_overflow) fputs(",\"truncated\":true", f);

    fputs(",\"report\":{", f);
    for (int i = 0; i < g_rep_n; i++) {
        if (i) fputc(',', f);
        json_str(f, g_rep[i].key);
        fputc(':', f);
        if (g_rep[i].is_int) fputs(g_rep[i].val, f);
        else                 json_str(f, g_rep[i].val);
    }
    fputs("}", f);

    fputs(",\"results\":[", f);
    for (int i = 0; i < g_n; i++) {
        if (i) fputc(',', f);
        fputs("{\"id\":", f);      json_str(f, g_res[i].id);
        fputs(",\"status\":", f);  json_str(f, status_name(g_res[i].status));
        fputs(",\"title\":", f);   json_str(f, g_res[i].title);
        fputs(",\"detail\":", f);  json_str(f, g_res[i].detail);
        fputc('}', f);
    }
    fputs("]}\n", f);
}

static void emit_json(const char* json_path, const char* verdict) {
    printf("\n---BEGIN-CLEONA-CONFORMANCE-JSON---\n");
    write_json(stdout, verdict);
    printf("---END-CLEONA-CONFORMANCE-JSON---\n");
    fflush(stdout);

    if (json_path && json_path[0]) {
        FILE* f = fopen(json_path, "wb");
        if (!f) {
            printf("WARN could not write %s\n", json_path);
            return;
        }
        write_json(f, verdict);
        fclose(f);
        printf("json written to %s\n", json_path);
    }
}

int ch_abort(const char* reason) {
    snprintf(g_fatal, sizeof(g_fatal), "%s", reason ? reason : "aborted");
    printf("\nFATAL %s\n", g_fatal);
    printf("The backend could not be exercised. This is a conformance failure, "
           "not a skipped test.\n");
    emit_json(NULL, "fatal");
    return 2;
}

int ch_end(const char* json_path, const char* const* expect_fail, int expect_n) {
    printf("=========================================================================\n");

    /* One grep-able line carrying the whole verdict, for logs that keep only
     * the tail of a device run. */
    printf("SUMMARY checks=%d failures=%d failed_ids=", g_n, g_fail);
    int printed = 0;
    for (int i = 0; i < g_n; i++) {
        if (g_res[i].status != CH_FAIL) continue;
        printf("%s%s", printed ? "," : "", g_res[i].id);
        printed++;
    }
    if (!printed) printf("-");
    printf("\n");

    if (expect_n <= 0) {
        const char* verdict = (g_fail == 0) ? "pass" : "fail";
        printf("RESULT %s\n", g_fail == 0 ? "CONFORMANT" : "NOT CONFORMANT");
        emit_json(json_path, verdict);
        return g_fail == 0 ? 0 : 1;
    }

    /* --expect-fail: the harness self-test. Exactly the listed ids must have
     * failed — no more, no fewer. */
    int matched = 0, unexpected = 0, missing = 0;
    for (int i = 0; i < g_n; i++) {
        if (g_res[i].status != CH_FAIL) continue;
        int found = 0;
        for (int e = 0; e < expect_n; e++) {
            if (strcmp(g_res[i].id, expect_fail[e]) == 0) { found = 1; break; }
        }
        if (found) matched++; else {
            unexpected++;
            printf("  unexpected failure: %s\n", g_res[i].id);
        }
    }
    for (int e = 0; e < expect_n; e++) {
        int found = 0;
        for (int i = 0; i < g_n; i++) {
            if (g_res[i].status == CH_FAIL &&
                strcmp(g_res[i].id, expect_fail[e]) == 0) { found = 1; break; }
        }
        if (!found) {
            missing++;
            printf("  expected failure did NOT happen: %s\n", expect_fail[e]);
        }
    }

    int ok = (unexpected == 0) && (missing == 0) && (matched == expect_n);
    printf("EXPECT-FAIL matched=%d unexpected=%d missing=%d\n",
           matched, unexpected, missing);
    printf("RESULT %s\n", ok ? "NEGATIVE CONTROL OK (the harness caught exactly "
                               "the injected defect)"
                             : "NEGATIVE CONTROL BROKEN");
    emit_json(json_path, ok ? "negative-control-ok" : "negative-control-broken");
    return ok ? 0 : 1;
}
