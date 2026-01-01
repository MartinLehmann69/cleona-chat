// The --media mode of cleona-play (cleona_play_media.cpp, Windows only).
#ifndef CLEONA_PLAY_MEDIA_H_
#define CLEONA_PLAY_MEDIA_H_

#ifdef __cplusplus
extern "C" {
#endif

// Plays the audio at [url] (a file path or http URL) through Media Foundation
// from [start_ms] on, or with [probe_only] writes its duration in milliseconds
// to stdout. Returns an exit code of cleona_play.c (8: Media Foundation could
// not be started on this system).
int cleona_play_media(const wchar_t* url, int probe_only, long long start_ms,
                      double volume);

#ifdef __cplusplus
}
#endif

#endif  // CLEONA_PLAY_MEDIA_H_
