# Yubal

Yubal downloads YouTube Music albums, playlists, and regular YouTube music
videos into Plex-friendly audio files. The web UI is available at
`https://yubal.jaw.dev` behind the admin OAuth policy.

## iPhone workflow

1. Create an **unlisted** YouTube playlist named `Burmese Music Inbox`.
2. Add Burmese songs to it from the YouTube iOS app.
3. Open Yubal, subscribe to the playlist URL, and start the first sync.
4. Yubal checks subscriptions daily at 10:00 PM.
5. Listen in Plexamp after Plex scans the library.

No YouTube cookies are required for public or unlisted playlists. Avoid adding
account cookies unless a private playlist requires them; cookie-based downloads
can trigger stricter YouTube account rate limits.

## One-time Plex setup

Create a separate Plex **Music** library named `YouTube Music` and select the
container path `/youtube-music`. Enable **Prefer local metadata** so Yubal's
embedded title, artist, album art, lyrics, and Burmese Unicode tags are used.
Start with 10-20 songs and check their metadata before importing a large list.

The compose configuration deliberately keeps this library separate from
`/music`, so Lidarr cannot rename or delete YouTube downloads.

## Formats and playlists

Audio is stored as M4A for direct Plex/iOS compatibility. Burmese characters
are preserved, regular YouTube videos are allowed, ReplayGain is applied, and
lyrics are fetched when available. Files live on the NAS at
`/home/jaw/plex/youtube-music`; only Yubal's config and subscription database
under `/home/jaw/data/yubal` are included in Backrest.

Yubal writes M3U files under `_Playlists`, but Plex does not import M3U files
itself. If Plex playlists are important, use ListPorter manually after the
library scan. It needs a Plex token and music library ID, so it is intentionally
not deployed as an unattended container.

Only archive media you are allowed to download. YouTube extraction can break
when YouTube changes its site; update Yubal through Renovate when that happens.
