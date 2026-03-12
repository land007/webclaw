#!/usr/bin/env python3
"""PulseAudio null-sink -> WebSocket audio stream (Opus 64kbps, 48000Hz, stereo)
Full-duplex: also accepts inbound binary messages from browser mic and writes
them into a webcode_input null-sink via pacat --playback.
Text frames: JSON control messages for server-side ffmpeg recording.

Compression: Opus @ 64 Kbps, 20ms frames (960 samples/ch @ 48000Hz).
Bandwidth: 1.37 Mbps (raw PCM) -> 64 Kbps (Opus) = ~95% reduction.
Latency:   ~186ms (raw chunk) -> ~20ms (Opus frame) = ~89% reduction.
"""
import asyncio
import os
import subprocess
import sys
import websockets
import json
import signal
import datetime
import opuslib

HOST = "127.0.0.1"
PORT = int(os.environ.get("AUDIO_PORT", "10006"))
SAMPLE_RATE = 48000       # Opus native rate (upsample from 44100)
CHANNELS = 2
FRAME_SIZE = 960          # 20ms per frame at 48000Hz
CHUNK_BYTES = FRAME_SIZE * CHANNELS * 2  # raw PCM bytes per Opus frame
ENCODER_BITRATE = 64000   # 64 Kbps target
PULSE_SINK = "webcode_null"
PULSE_INPUT_SINK = "webcode_input"
CLIENTS = set()
# Track which clients want audio output (to avoid pushing when only mic is active)
AUDIO_PLAYING_CLIENTS = set()
PCM_CLIENTS = set()  # clients that requested PCM instead of Opus

# PulseAudio socket path
PULSE_SOCKET = "/run/user/1000/pulse/native"
PULSE_ENV = {**os.environ, "PULSE_SERVER": f"unix:{PULSE_SOCKET}"}

# pacat --playback subprocess for microphone input
pacat_in_proc = None

# ffmpeg recording state
ffmpeg_proc = None
recording_filename = None
RECORDINGS_DIR = "/home/ubuntu/recordings"


def _get_display_resolution(display):
    """Query actual X11 display size via xdpyinfo (avoids VNC_RESOLUTION mismatch)."""
    import re
    try:
        result = subprocess.run(
            ["xdpyinfo", "-display", display],
            capture_output=True, text=True, timeout=3,
            env={**os.environ, "DISPLAY": display},
        )
        m = re.search(r'dimensions:\s+(\d+x\d+)', result.stdout)
        if m:
            return m.group(1)
    except Exception:
        pass
    # fallback to env var
    vnc_res = os.environ.get("VNC_RESOLUTION", "1920x1080")
    if not re.match(r'^\d+x\d+$', vnc_res):
        vnc_res = "1920x1080"
    return vnc_res


def _build_ffmpeg_cmd(filename):
    display = os.environ.get("DISPLAY", ":1")
    res = _get_display_resolution(display)
    print(f"[audio-ws] Recording resolution: {res}", flush=True)
    return [
        "ffmpeg", "-y",
        "-f", "x11grab", "-framerate", "30",
        "-video_size", res,
        "-i", f"{display}.0+0,0",
        "-f", "pulse", "-i", f"{PULSE_SINK}.monitor",
        "-c:v", "libx264", "-preset", "fast", "-crf", "23",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        filename,
    ]


async def start_recording():
    global ffmpeg_proc, recording_filename
    if ffmpeg_proc is not None and ffmpeg_proc.returncode is None:
        return None, "already_recording"
    os.makedirs(RECORDINGS_DIR, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    recording_filename = os.path.join(RECORDINGS_DIR, f"recording_{ts}.mp4")
    cmd = _build_ffmpeg_cmd(recording_filename)
    print(f"[audio-ws] Starting recording: {recording_filename}", flush=True)
    try:
        ffmpeg_proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**PULSE_ENV, "DISPLAY": os.environ.get("DISPLAY", ":1")},
        )
        asyncio.ensure_future(_drain_ffmpeg_stderr())
        return recording_filename, None
    except Exception as e:
        ffmpeg_proc = None
        recording_filename = None
        return None, str(e)


async def _drain_ffmpeg_stderr():
    if not ffmpeg_proc:
        return
    try:
        while True:
            line = await ffmpeg_proc.stderr.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="replace").strip()
            if text and not text.startswith("frame="):
                print(f"[ffmpeg] {text}", flush=True)
    except Exception:
        pass


async def stop_recording():
    global ffmpeg_proc, recording_filename
    if ffmpeg_proc is None or ffmpeg_proc.returncode is not None:
        return None, "not_recording"
    fname = recording_filename
    try:
        ffmpeg_proc.send_signal(signal.SIGINT)
        try:
            await asyncio.wait_for(ffmpeg_proc.wait(), timeout=10.0)
        except asyncio.TimeoutError:
            ffmpeg_proc.kill()
            await ffmpeg_proc.wait()
        print(f"[audio-ws] Recording saved: {fname}", flush=True)
    except Exception as e:
        return None, str(e)
    finally:
        ffmpeg_proc = None
        recording_filename = None
    return fname, None


async def broadcast_audio():
    """Read audio from pacat, encode with Opus, broadcast to all WebSocket clients.

    Codec: Opus, 48000Hz stereo, 64 Kbps, 20ms frames (APPLICATION_RESTRICTED_LOWDELAY).
    Each WebSocket message is one raw Opus packet (~160 bytes vs 3840 bytes raw PCM).
    """
    encoder = opuslib.Encoder(SAMPLE_RATE, CHANNELS, 'restricted_lowdelay')
    encoder.bitrate = ENCODER_BITRATE
    encoder.complexity = 5  # balance quality vs CPU for real-time use

    cmd = [
        "pacat", "--record",
        "-d", f"{PULSE_SINK}.monitor",
        "--format=s16le",
        f"--rate={SAMPLE_RATE}",
        f"--channels={CHANNELS}",
        "--latency-msec=5",
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=PULSE_ENV,
    )
    print(
        f"[audio-ws] pacat started (pid={proc.pid}), "
        f"Opus {ENCODER_BITRATE // 1000}kbps @ {SAMPLE_RATE}Hz "
        f"20ms frames → ws://{HOST}:{PORT}",
        flush=True,
    )

    try:
        while True:
            try:
                frame_pcm = await proc.stdout.readexactly(CHUNK_BYTES)
            except asyncio.IncompleteReadError:
                print(f"[audio-ws] pacat EOF, exit code={await proc.wait()}", flush=True)
                break

            try:
                encoded = encoder.encode(frame_pcm, FRAME_SIZE)
            except Exception as e:
                print(f"[audio-ws] Opus encode error: {e}", flush=True)
                continue

            if AUDIO_PLAYING_CLIENTS:
                dead = set()
                for client in list(AUDIO_PLAYING_CLIENTS):
                    try:
                        data = frame_pcm if client in PCM_CLIENTS else encoded
                        await client.send(data)
                    except Exception:
                        dead.add(client)
                AUDIO_PLAYING_CLIENTS.difference_update(dead)
                PCM_CLIENTS.difference_update(dead)
    except Exception as e:
        print(f"[audio-ws] broadcast_audio error: {e}", flush=True)
    finally:
        try:
            proc.terminate()
            await proc.wait()
        except Exception:
            pass


async def handler(ws):
    """Handle WebSocket client connection (full-duplex)."""
    CLIENTS.add(ws)
    print(f"[audio-ws] client connected ({len(CLIENTS)} total) from {ws.remote_address}", flush=True)

    # Send codec negotiation so the client knows to use Opus decoder
    try:
        await ws.send(json.dumps({
            "event": "codec_info",
            "codec": "opus",
            "sample_rate": SAMPLE_RATE,
            "channels": CHANNELS,
            "frame_size": FRAME_SIZE,
            "bitrate": ENCODER_BITRATE,
        }))
    except Exception as e:
        print(f"[audio-ws] codec_info send failed: {e}", flush=True)

    # Mic decoder state for this client
    mic_decoder = None
    mic_codec_opus = False

    try:
        async for message in ws:
            if isinstance(message, bytes):
                if pacat_in_proc and pacat_in_proc.stdin:
                    try:
                        if mic_codec_opus and mic_decoder:
                            # Decode Opus packet to PCM
                            try:
                                pcm = mic_decoder.decode(bytes(message), FRAME_SIZE)
                                pacat_in_proc.stdin.write(pcm)
                                await pacat_in_proc.stdin.drain()
                            except Exception as e:
                                print(f"[audio-ws] mic Opus decode error: {e}", flush=True)
                        else:
                            # Raw PCM (fallback)
                            pacat_in_proc.stdin.write(message)
                            await pacat_in_proc.stdin.drain()
                    except Exception as e:
                        print(f"[audio-ws] mic input write error: {e}", flush=True)
            elif isinstance(message, str):
                try:
                    cmd = json.loads(message)
                except json.JSONDecodeError:
                    continue
                action = cmd.get("action")

                if action == "set_audio":
                    # Client tells us whether they're playing audio
                    should_send = cmd.get("enabled", False)
                    if should_send:
                        AUDIO_PLAYING_CLIENTS.add(ws)
                        if cmd.get("prefer_pcm", False):
                            PCM_CLIENTS.add(ws)
                            print(f"[audio-ws] client enabled audio output in PCM mode ({len(AUDIO_PLAYING_CLIENTS)} playing)", flush=True)
                            # Re-announce PCM codec so client's onmessage knows the mode
                            try:
                                await ws.send(json.dumps({
                                    "event": "codec_info",
                                    "codec": "pcm",
                                    "sample_rate": SAMPLE_RATE,
                                    "channels": CHANNELS,
                                    "frame_size": FRAME_SIZE,
                                }))
                            except Exception as e:
                                print(f"[audio-ws] pcm codec_info send failed: {e}", flush=True)
                        else:
                            print(f"[audio-ws] client enabled audio output ({len(AUDIO_PLAYING_CLIENTS)} playing)", flush=True)
                    else:
                        AUDIO_PLAYING_CLIENTS.discard(ws)
                        PCM_CLIENTS.discard(ws)
                        print(f"[audio-ws] client disabled audio output ({len(AUDIO_PLAYING_CLIENTS)} playing)", flush=True)

                elif action == "mic_codec":
                    # Client announces mic codec support
                    if cmd.get("codec") == "opus":
                        try:
                            mic_decoder = opuslib.Decoder(SAMPLE_RATE, CHANNELS)
                            mic_codec_opus = True
                            print(f"[audio-ws] client mic Opus decoder ready", flush=True)
                        except Exception as e:
                            print(f"[audio-ws] failed to create mic Opus decoder: {e}", flush=True)

                elif action == "start_recording":
                    fname, err = await start_recording()
                    resp = {"event": "recording_error", "error": err} if err else \
                           {"event": "recording_started", "filename": os.path.basename(fname)}
                elif action == "stop_recording":
                    fname, err = await stop_recording()
                    resp = {"event": "recording_error", "error": err} if err else \
                           {"event": "recording_stopped", "filename": os.path.basename(fname)}
                elif action == "recording_status":
                    is_rec = ffmpeg_proc is not None and ffmpeg_proc.returncode is None
                    resp = {"event": "recording_status", "recording": is_rec,
                            "filename": os.path.basename(recording_filename) if recording_filename else None}
                else:
                    continue
                try:
                    await ws.send(json.dumps(resp))
                except Exception:
                    pass
    except Exception:
        pass
    finally:
        CLIENTS.discard(ws)
        AUDIO_PLAYING_CLIENTS.discard(ws)
        PCM_CLIENTS.discard(ws)
        print(f"[audio-ws] client disconnected ({len(CLIENTS)} remaining, {len(AUDIO_PLAYING_CLIENTS)} playing)", flush=True)


async def wait_for_pulseaudio(retries=30):
    """Wait for PulseAudio to be ready."""
    for i in range(retries):
        try:
            result = subprocess.run(
                ["pactl", "info"],
                capture_output=True,
                env=PULSE_ENV,
                timeout=2,
            )
            if result.returncode == 0:
                print("[audio-ws] PulseAudio is ready", flush=True)
                return True
        except Exception:
            pass
        print(f"[audio-ws] waiting for PulseAudio ({i+1}/{retries})...", flush=True)
        await asyncio.sleep(1)
    print("[audio-ws] ERROR: PulseAudio did not start in time", flush=True)
    return False


async def wait_for_null_sink(retries=10):
    """Wait for webcode_null sink to be available."""
    for i in range(retries):
        try:
            result = subprocess.run(
                ["pactl", "list", "sinks", "short"],
                capture_output=True,
                text=True,
                env=PULSE_ENV,
                timeout=2,
            )
            if PULSE_SINK in result.stdout:
                print(f"[audio-ws] null-sink '{PULSE_SINK}' is available", flush=True)
                return True
        except Exception:
            pass
        print(f"[audio-ws] waiting for null-sink '{PULSE_SINK}' ({i+1}/{retries})...", flush=True)
        await asyncio.sleep(1)
    print(f"[audio-ws] WARNING: null-sink '{PULSE_SINK}' not found, pacat may fail", flush=True)
    return False


async def setup_null_sink():
    """Create null-sink if it doesn't exist."""
    try:
        result = subprocess.run(
            ["pactl", "list", "sinks", "short"],
            capture_output=True,
            text=True,
            env=PULSE_ENV,
        )
        if PULSE_SINK in result.stdout:
            print(f"[audio-ws] null-sink '{PULSE_SINK}' already exists", flush=True)
        else:
            subprocess.run(
                [
                    "pactl", "load-module", "module-null-sink",
                    f"sink_name={PULSE_SINK}",
                    "sink_properties=device.description=WebcodeAudio",
                ],
                env=PULSE_ENV,
                check=True,
            )
            print(f"[audio-ws] null-sink '{PULSE_SINK}' created", flush=True)

        subprocess.run(
            ["pactl", "set-default-sink", PULSE_SINK],
            env=PULSE_ENV,
            check=True,
        )
        print(f"[audio-ws] default sink set to '{PULSE_SINK}'", flush=True)
    except subprocess.CalledProcessError as e:
        print(f"[audio-ws] ERROR setting up null-sink: {e}", flush=True)


async def setup_input_sink():
    """Create webcode_input null-sink and wrap its monitor as a normal source.

    Chrome filters out PA_SOURCE_MONITOR sources during getUserMedia enumeration.
    module-remap-source wraps webcode_input.monitor into a plain source 'webcode_mic'
    without the MONITOR flag, so Chrome can enumerate and select it.
    """
    try:
        # 1. Create webcode_input null-sink if missing
        result = subprocess.run(
            ["pactl", "list", "sinks", "short"],
            capture_output=True,
            text=True,
            env=PULSE_ENV,
        )
        if PULSE_INPUT_SINK in result.stdout:
            print(f"[audio-ws] null-sink '{PULSE_INPUT_SINK}' already exists", flush=True)
        else:
            subprocess.run(
                [
                    "pactl", "load-module", "module-null-sink",
                    f"sink_name={PULSE_INPUT_SINK}",
                    "sink_properties=device.description=WebcodeMic",
                ],
                env=PULSE_ENV,
                check=True,
            )
            print(f"[audio-ws] null-sink '{PULSE_INPUT_SINK}' created", flush=True)

        # 2. Wrap webcode_input.monitor as plain source 'webcode_mic' (no MONITOR flag)
        src_result = subprocess.run(
            ["pactl", "list", "sources", "short"],
            capture_output=True,
            text=True,
            env=PULSE_ENV,
        )
        if "webcode_mic" in src_result.stdout:
            print("[audio-ws] remap-source 'webcode_mic' already exists", flush=True)
        else:
            subprocess.run(
                [
                    "pactl", "load-module", "module-remap-source",
                    "source_name=webcode_mic",
                    f"master={PULSE_INPUT_SINK}.monitor",
                    "source_properties=device.description=WebcodeMicrophone",
                ],
                env=PULSE_ENV,
                check=True,
            )
            print("[audio-ws] remap-source 'webcode_mic' created", flush=True)

        # 3. Set webcode_mic as default source
        subprocess.run(
            ["pactl", "set-default-source", "webcode_mic"],
            env=PULSE_ENV,
            check=True,
        )
        print("[audio-ws] default source set to 'webcode_mic'", flush=True)

    except subprocess.CalledProcessError as e:
        print(f"[audio-ws] ERROR setting up input sink: {e}", flush=True)


async def start_input_playback():
    """Start pacat --playback to feed browser mic audio into webcode_input."""
    global pacat_in_proc
    cmd = [
        "pacat", "--playback",
        "-d", PULSE_INPUT_SINK,
        "--format=s16le",
        f"--rate={SAMPLE_RATE}",
        f"--channels={CHANNELS}",
        "--latency-msec=20",
    ]
    pacat_in_proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdin=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=PULSE_ENV,
    )
    print(f"[audio-ws] pacat --playback started (pid={pacat_in_proc.pid}) for mic input", flush=True)


async def main():
    import atexit

    def _cleanup():
        if ffmpeg_proc and ffmpeg_proc.returncode is None:
            try:
                ffmpeg_proc.send_signal(signal.SIGINT)
            except Exception:
                pass

    atexit.register(_cleanup)

    if not await wait_for_pulseaudio():
        sys.exit(1)

    await setup_null_sink()
    await wait_for_null_sink()
    await setup_input_sink()
    await start_input_playback()

    async with websockets.serve(handler, HOST, PORT):
        print(f"[audio-ws] WebSocket server listening on ws://{HOST}:{PORT}", flush=True)
        await broadcast_audio()


if __name__ == "__main__":
    asyncio.run(main())
