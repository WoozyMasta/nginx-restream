# nginx-restream

Static nginx + nginx-rtmp-module image for multi-platform RTMP restreaming.

The image is built as a static nginx binary
and packed into a scratch runtime image.  
It accepts one RTMP publisher and pushes the stream to one or more platforms
simultaneously using stream keys passed as query args -
no ffmpeg, no shell, no HTTP callbacks required.

Stream flow:

```text
OBS/ffmpeg -> nginx-restream -> YouTube
                             -> Twitch
                             -> Facebook
                             -> ... any platform
```

No transcoding is performed.
The incoming stream must already be compatible with the target platforms.

## Features

* Static nginx binary, scratch runtime image
* nginx-rtmp-module with dynamic push and TLS (RTMPS) support
* Multi-platform restream via RTMP query args -
  no config change needed
* RTMP ingest on port 1935
* Stream key is not baked into the image
* No ffmpeg, no shell in runtime image
* Two image variants: `latest` (with HTTP stats) and `slim` (RTMP only)

## RTMP URL

Pass platform stream keys as query args:

```text
rtmp://SERVER_IP:1935/restream/live?yt=YOUTUBE_KEY&tw=TWITCH_KEY
```

OBS settings:

```text
Server:     rtmp://SERVER_IP:1935/restream/live
Stream Key: ?yt=YOUTUBE_KEY&tw=TWITCH_KEY
```

Or use a single platform without query args by setting only one arg in the URL.

## Build locally

```bash
docker build -t nginx-restream:slim   --build-arg WITH_STATS=0 .
docker build -t nginx-restream:latest --build-arg WITH_STATS=1 .
```

Check nginx build flags:

```bash
docker run --rm nginx-restream -V
```

Check config:

```bash
docker run --rm nginx-restream -t
```

Run:

```bash
docker run --rm -ti -p 1935:1935 nginx-restream:slim
docker run --rm -ti -p 1935:1935 -p 8080:8080 nginx-restream:latest
```

## Run with host network

Recommended on Linux VPS - the host firewall sees the real source IP.

```bash
docker run -d \
  --name nginx-restream \
  --restart unless-stopped \
  --network host \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m,mode=1777 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  nginx-restream:latest
```

## Test stream

```bash
ffmpeg -re \
  -f lavfi -i testsrc2=size=2560x1440:rate=60 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v libx264 -preset veryfast \
  -b:v 26000k -maxrate 26000k -bufsize 52000k -g 120 \
  -c:a aac -b:a 192k -ar 48000 \
  -f flv "rtmp://SERVER_IP:1935/restream/live?yt=YOUTUBE_KEY"
```

## OBS settings

Recommended baseline for 1440p60:

```text
Encoder:           H.264
Rate control:      CBR
Bitrate:           24000-28000 Kbps
Keyframe interval: 2s
Audio codec:       AAC
Audio bitrate:     160-320 Kbps
```

The VPS does not transcode. CPU load should be low.
Network egress must handle the full stream bitrate multiplied
by the number of target platforms.

## Security notes

Do not expose port 1935 publicly.
Edit `config/access.conf` and whitelist your encoder IP before deploying:

```nginx
allow publish 1.2.3.4;
deny  publish all;
deny  play    all;
```

The stream key is not stored in the image or config,
but it is visible to the RTMP client and may appear in client logs,
shell history, or packet captures.

The HTTP stats endpoint (port 8080) is restricted to private network ranges
by default (`config/stats.conf`). Do not expose port 8080 publicly.

RTMP ingest is plaintext.
For encrypted ingest, place a TLS termination proxy
(e.g. stunnel, nginx stream with ssl) in front of port 1935.
Outgoing pushes to platforms that require RTMPS (Facebook, Kick)
use TLS natively -
certificate verification is disabled for outgoing relays since destination URLs
are fixed in the nginx config by the administrator.
