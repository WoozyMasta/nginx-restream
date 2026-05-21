# nginx-restream

Static nginx + nginx-rtmp-module image for multi-platform RTMP restreaming.

The image is built as a static nginx binary
and packed into a scratch runtime image.
It accepts one RTMP publisher and pushes the stream to one or more platforms
simultaneously using stream keys passed as query args -
no shell, no HTTP callbacks required.

Stream flow:

```text
OBS/ffmpeg -> nginx-restream -> YouTube
                             -> Twitch
                             -> Facebook
                             -> ... any platform
```

No transcoding is performed by default.
The incoming stream must already be compatible with the target platforms.
The `latest` image includes ffmpeg for optional transcoding via `exec`.

Built on a fork of
[nginx-rtmp-module](https://github.com/WoozyMasta/nginx-rtmp-module)
that adds three features not present in the original:

* **TLS outbound (RTMPS)** -
  outgoing pushes to platforms that require `rtmps://`
  work natively without an external stunnel
* **Dynamic push** -
  stream keys are passed as RTMP query args at publish time,
  so one running nginx can fan out
  to any set of platforms without a config reload
* **Dynamic exec** -
  spawn an ffmpeg transcoder only when a specific query arg is present;
  each destination can have its own independent ffmpeg process
  and its own encoding parameters

## Features

* Static nginx binary, scratch runtime image
* RTMP ingest on port 1935
* Multi-platform restream via query args - no config change needed
* Per-destination conditional transcoding via `dynamic_exec_arg`
* Stream key is not baked into the image
* No shell in runtime image
* Two image variants: `latest` (nginx + ffmpeg + HTTP stats)
  and `slim` (nginx only)

## Images

* [`ghcr.io/woozymasta/nginx-restream`](https://github.com/WoozyMasta/nginx-restream/pkgs/container/nginx-restream)
* [`docker.io/woozymasta/nginx-restream`](https://hub.docker.com/r/woozymasta/nginx-restream)

```bash
docker pull ghcr.io/woozymasta/nginx-restream:latest
docker pull ghcr.io/woozymasta/nginx-restream:slim
```

Two variants are published:

* `latest` - nginx + ffmpeg + HTTP stats endpoint on port 8080
* `slim` - nginx only, no ffmpeg, no HTTP server, smallest image size
* `X.Y.Z` / `X.Y.Z-slim` - versioned releases of each variant

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

## Transcoding with ffmpeg

The `latest` image includes a statically built ffmpeg.
Use it when platforms have different bitrate limits
or when the source stream needs to be downscaled before pushing.

nginx-rtmp starts ffmpeg automatically when a stream is published
and kills it when the stream stops.
The `$args` variable forwards platform query args from the encoder URL through
to the destination application.

### All platforms transcoded

The encoder pushes a high-bitrate stream;
ffmpeg re-encodes it and forwards the result to the restream application.

```nginx
application transcode {
    live on;
    record off;

    exec /bin/ffmpeg
        -loglevel warning
        -i rtmp://127.0.0.1:1935/transcode/$name
        -c:v libx264 -preset veryfast
        -b:v 5500k -maxrate 5500k -bufsize 11000k
        -vf scale=1920:1080
        -r 60
        -c:a aac -b:a 160k -ar 48000
        -f flv rtmp://127.0.0.1:1935/restream/live?$args;
}

application restream {
    live on;
    record off;

    dynamic_push_arg yt rtmp://a.rtmp.youtube.com/live2;
    dynamic_push_arg tw rtmp://live.twitch.tv/app;
}
```

```text
Server:     rtmp://SERVER_IP:1935/transcode/live
Stream Key: ?yt=YOUTUBE_KEY&tw=TWITCH_KEY
```

### Per-destination transcoding with dynamic_exec_arg

`dynamic_exec_arg` spawns a separate ffmpeg only when the matching query arg
is present. Each destination gets its own encoding parameters.
No wasted CPU, no extra applications.

YouTube accepts high bitrates directly; Twitch and other platforms may cap
at 6000 kbps. Push the original to YouTube and transcode only for the rest:

```nginx
application live {
    live on;
    record off;

    # Direct push to YouTube - no transcoding
    dynamic_push_arg yt rtmp://a.rtmp.youtube.com/live2;

    # ffmpeg spawns only when ?tw=KEY is present
    dynamic_exec_arg tw /bin/ffmpeg
        -loglevel warning
        -i rtmp://127.0.0.1:1935/live/$name
        -c:v libx264 -preset veryfast
        -b:v 5500k -maxrate 5500k -bufsize 11000k
        -vf scale=1920:1080
        -r 60
        -c:a aac -b:a 160k -ar 48000
        -f flv rtmp://live.twitch.tv/app/$value;

    # Independent ffmpeg spawns only when ?vk=KEY is present
    dynamic_exec_arg vk /bin/ffmpeg
        -loglevel warning
        -i rtmp://127.0.0.1:1935/live/$name
        -c:v libx264 -preset veryfast
        -b:v 4000k -maxrate 4000k -bufsize 8000k
        -vf scale=1280:720
        -r 30
        -c:a aac -b:a 128k -ar 48000
        -f flv rtmp://ovsu.mycdn.me/input/$value;
}
```

```text
Server:     rtmp://SERVER_IP:1935/live/live
Stream Key: ?yt=YOUTUBE_KEY&tw=TWITCH_KEY&vk=VK_KEY
```

Available variables in `dynamic_exec_arg` commands:
`$name` (stream name), `$value` (the matched arg value — the stream key),
`$app` (application name), `$args` (full query string).

## Build locally

```bash
# Full image: nginx + rtmp module + ffmpeg + HTTP stats
docker build -t nginx-restream:latest -f Dockerfile .

# Slim image: nginx with rtmp module only
docker build -t nginx-restream:slim -f Dockerfile.slim .
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
  --tmpfs /tmp:rw,noexec,nosuid,size=64m,mode=1777 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  ghcr.io/woozymasta/nginx-restream:latest
```

> [!NOTE]
> The `latest` image runs ffmpeg as a subprocess of nginx.  
> Increase tmpfs size if you expect multiple concurrent transcoding sessions.

## Custom configuration

### Override individual config files

Mount any of the three config files to replace the defaults:

```bash
# Override only the access rules
docker run -d \
  --network host \
  -v /etc/nginx-restream/access.conf:/config/access.conf:ro \
  ghcr.io/woozymasta/nginx-restream:latest

# Override all three
docker run -d \
  --network host \
  -v /etc/nginx-restream/restream.conf:/config/restream.conf:ro \
  -v /etc/nginx-restream/access.conf:/config/access.conf:ro \
  -v /etc/nginx-restream/stats.conf:/config/stats.conf:ro \
  ghcr.io/woozymasta/nginx-restream:latest
```

Config files shipped in the image:

* `/config/restream.conf` - main nginx config with the `restream` application
* `/config/access.conf` - RTMP publish allow/deny rules
* `/config/stats.conf` - HTTP stats server on port 8080

### Use the transcoding config

The image ships `config/restream-transcode.conf` as an example configuration
with `dynamic_exec_arg` — YouTube receives the original stream,
other platforms get independently transcoded copies.

```bash
docker run -d \
  --network host \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m,mode=1777 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  ghcr.io/woozymasta/nginx-restream:latest \
  -c /config/restream-transcode.conf -g "daemon off;"
```

Or mount your own config:

```bash
docker run -d \
  --network host \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m,mode=1777 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  -v /etc/nginx-restream/my.conf:/config/my.conf:ro \
  -v /etc/nginx-restream/access.conf:/config/access.conf:ro \
  ghcr.io/woozymasta/nginx-restream:latest \
  -c /config/my.conf -g "daemon off;"
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

The VPS does not transcode by default. CPU load should be low.
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
