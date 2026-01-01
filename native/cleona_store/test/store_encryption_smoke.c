/* Gate: the local store lies encrypted on disk (S366).
 *
 * NOT a performance test. This gate checks exactly the statement that the
 * architecture makes — not a value that happens to coincide with it:
 *
 *   1. A file created with a key does NOT carry the SQLite header
 *      "SQLite format 3\0". That is the statement itself, checked at the byte.
 *   2. Without a key it cannot be opened.
 *   3. With a wrong key it cannot be opened.
 *   4. With the right key the data are there.
 *   5. FTS5 is present and finds the text (the search is the reason for the
 *      whole conversion).
 *   6. The journal likewise carries no plaintext header.
 *
 * REVERSE PROBE. With -DCLEONA_STORE_SABOTAGE the same source is compiled without
 * key. Then this program MUST fail. If it does
 * not, it does not measure the encryption but something else,
 * and would be worthless as a gate (pattern from native/cleona_link/, S336: three
 * gates were green without ever having checked anything).
 *
 * Build and run: see header of native/cleona_store/CMakeLists.txt.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sqlite3mc_amalgamation.h"

/* 32 bytes, hex-encoded — in the app the key comes from
 * HdWallet.deriveFileEncKey(master_seed, hd_index) and never from here.
 *
 * It is passed as `PRAGMA hexkey`, not as `PRAGMA key`: `key`
 * takes a passphrase and derives from it, `hexkey` takes the 32 bytes
 * directly. Exactly that is what we want — the key is already derived from the
 * seed, a second derivation on top would bring nothing. (The
 * blob notation `PRAGMA key = x'..'` is ruled out in addition: with
 * SQLITE_DQS=0 there is no quotation form in which it would get through the
 * parser.) */
#define KEY_RIGHT "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
#define KEY_WRONG     "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"

static int failures = 0;

static void check(int condition, const char *what) {
  if (condition) {
    printf("  ok    %s\n", what);
  } else {
    printf("  FAIL  %s\n", what);
    failures++;
  }
}

/* Sets the key — except in the sabotage compilation. */
static int set_key(sqlite3 *db, const char *key) {
#ifdef CLEONA_STORE_SABOTAGE
  (void)db; (void)key;
  return SQLITE_OK; /* deliberately: no encryption */
#else
  char sql[256];
  snprintf(sql, sizeof sql, "PRAGMA hexkey = '%s';", key);
  return sqlite3_exec(db, sql, 0, 0, 0);
#endif
}

static int first_bytes(const char *path, char *buffer, size_t n) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  size_t got = fread(buffer, 1, n, f);
  fclose(f);
  return (int)got;
}

int main(void) {
  const char *path = "cleona_store_gate.db";
  remove(path);
  remove("cleona_store_gate.db-wal");
  remove("cleona_store_gate.db-shm");

#ifdef CLEONA_STORE_SABOTAGE
  printf("== Gate (SABOTAGE — without key; MUST fail) ==\n");
#else
  printf("== Gate: encrypted store ==\n");
#endif
  printf("  SQLite %s\n", sqlite3_libversion());

  sqlite3 *db = 0;
  if (sqlite3_open(path, &db) != SQLITE_OK) {
    printf("  FAIL  create file: %s\n", sqlite3_errmsg(db));
    return 1;
  }
  if (set_key(db, KEY_RIGHT) != SQLITE_OK) {
    printf("  FAIL  set key: %s\n", sqlite3_errmsg(db));
    return 1;
  }

  char *err = 0;
  int rc = sqlite3_exec(db,
      "PRAGMA journal_mode=WAL;"
      "CREATE TABLE message(id INTEGER PRIMARY KEY, txt TEXT);"
      "INSERT INTO message(txt) VALUES('contract from the station');"
      "CREATE VIRTUAL TABLE fts USING fts5(txt, content='message',"
      " content_rowid='id');"
      "INSERT INTO fts(fts) VALUES('rebuild');", 0, 0, &err);
  check(rc == SQLITE_OK, "table, FTS5 index and row created");
  if (err) { printf("        (%s)\n", err); sqlite3_free(err); }

  /* The data must really stand in the file before the header check. */
  sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", 0, 0, 0);
  sqlite3_close(db);

  /* 1. The file header — the actual statement. */
  char head[16] = {0};
  int n = first_bytes(path, head, sizeof head);
  check(n == (int)sizeof head, "file is readable and at least 16 B large");
  check(memcmp(head, "SQLite format 3", 15) != 0,
         "file header is NOT the SQLite plaintext header");

  /* 2. Without key. */
  db = 0;
  rc = sqlite3_open(path, &db);
  int without_key = sqlite3_exec(db, "SELECT count(*) FROM message;", 0, 0, 0);
  check(without_key != SQLITE_OK, "not readable without key");
  sqlite3_close(db);

  /* 3. With wrong key. */
  db = 0;
  sqlite3_open(path, &db);
  set_key(db, KEY_WRONG);
  int wrong_key = sqlite3_exec(db, "SELECT count(*) FROM message;", 0, 0, 0);
  check(wrong_key != SQLITE_OK, "not readable with a wrong key");
  sqlite3_close(db);

  /* 4./5. With the right key: data and full-text search. */
  db = 0;
  sqlite3_open(path, &db);
  set_key(db, KEY_RIGHT);
  sqlite3_stmt *st = 0;
  int hits = -1;
  if (sqlite3_prepare_v2(db,
        "SELECT count(*) FROM fts WHERE fts MATCH 'contract';", -1, &st, 0)
      == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW) {
    hits = sqlite3_column_int(st, 0);
  }
  sqlite3_finalize(st);
  check(hits == 1, "readable with the key, and FTS5 finds the text");

  /* 6. The journal must not carry a plaintext header either. */
  char wal[16] = {0};
  if (first_bytes("cleona_store_gate.db-wal", wal, sizeof wal) > 0) {
    /* The WAL header begins unencrypted with the magic 0x377f0682/0x377f0683. */
    int plaintext_wal = (unsigned char)wal[0] == 0x37 &&
                       (unsigned char)wal[1] == 0x7f &&
                       (unsigned char)wal[2] == 0x06;
    check(!plaintext_wal, "journal carries no plaintext header");
  } else {
    printf("  --    no journal present (expected after the checkpoint)\n");
  }
  sqlite3_close(db);

  remove(path);
  remove("cleona_store_gate.db-wal");
  remove("cleona_store_gate.db-shm");

  if (failures == 0) {
    printf("PASS\n");
    return 0;
  }
  printf("FAIL (%d)\n", failures);
  return 1;
}
