/* conformance_harness.h — result recording, output and exit policy.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 *
 * Deliberately duplicated between native/cleona_voice/test and
 * native/cleona_video/test instead of being shared from one place: a platform
 * package (V1.1-V1.4 / V1.13-V1.16) checks out and builds ONE of the two
 * directories, and a cross-directory include would drag the other ABI's tree
 * into an Android or iOS build for no benefit. The file is ~200 lines and has
 * no logic worth unifying — the checks are what matters, and those are not
 * duplicated.
 *
 * OUTPUT CONTRACT (both halves matter)
 * ------------------------------------
 * Human-readable: one line per check on stdout, aligned, PASS/FAIL/NOTE first
 * so a failure is findable with the eye and with grep.
 *
 * Machine-readable: one JSON object at the end, between the markers
 *     ---BEGIN-CLEONA-CONFORMANCE-JSON---
 *     ---END-CLEONA-CONFORMANCE-JSON---
 * so a platform package can paste the whole console output into its acceptance
 * report AND a script can still extract the structured result from the same
 * text. --json <path> additionally writes the object alone to a file.
 *
 * A NOTE is an observation, never a verdict. It exists because the ABI has
 * places where two different answers are both conformant (an encoder with no
 * forced-keyframe control, a device with one camera, a chain that cannot read
 * an effect state back). Turning those into PASS/FAIL would either reject a
 * legitimate backend or bless a broken one, so they are recorded verbatim and
 * left to the human reading the acceptance report.
 */

#ifndef CLEONA_CONFORMANCE_HARNESS_H
#define CLEONA_CONFORMANCE_HARNESS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CH_MAX_RESULTS 96
#define CH_MAX_EXPECT  16

typedef enum { CH_PASS = 0, CH_FAIL = 1, CH_NOTE = 2 } ch_status_t;

/* Starts a run. `suite` names the harness, `binding` and `library` describe how
 * the backend was reached (see conformance_abi.h). */
void ch_begin(const char* suite, const char* binding, const char* library);

/* Records one check. `ok` != 0 -> PASS. The detail string is free-form but must
 * carry the numbers the verdict was made from: a PASS whose evidence is not
 * printed cannot be re-checked by a reader, and a FAIL without numbers cannot
 * be diagnosed off-device. */
void ch_check(const char* id, const char* title, int ok, const char* fmt, ...);

/* Records an observation that cannot fail. */
void ch_note(const char* id, const char* title, const char* fmt, ...);

/* A key/value pair for the JSON "report" object — the verification report of
 * the backend under test (I11). Printed in the human section too. */
void ch_report_int(const char* key, int64_t value);
void ch_report_str(const char* key, const char* value);

/* Section header in the human output only. */
void ch_section(const char* name);

/* Aborts the run with a fatal reason (backend unusable). Prints, writes the
 * JSON, and returns the process exit code to use. */
int ch_abort(const char* reason);

/* Number of checks recorded so far with status FAIL. */
int ch_failures(void);

/* Ends the run and returns the process exit code.
 *
 * Normally: 0 when no check failed, 1 otherwise.
 *
 * When `expect_fail` is non-empty (harness self-test, --expect-fail), the
 * polarity is inverted and TIGHTENED: exit 0 only if the set of failed ids is
 * EXACTLY the expected set. Not "at least one failure" — a negative control
 * that accepts any failure proves only that something broke, not that the check
 * under examination is the one that caught it. */
int ch_end(const char* json_path, const char* const* expect_fail, int expect_n);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_CONFORMANCE_HARNESS_H */
