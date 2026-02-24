#!/bin/bash

# ===================================================================
#            SETUP SCRIPT YTLIVE STREAMER FOR DEBIAN/UBUNTU (v24 - USER PREFERENCE)
# ===================================================================

set -e # HENTIKAN SKRIP JIKA ADA ERROR [cite: 1]

# --- Variabel Konfigurasi ---
PYTHON_SCRIPT_NAME="ytlive" [cite: 1]
PYTHON_SCRIPT_PATH="/usr/local/bin/${PYTHON_SCRIPT_NAME}" [cite: 1]
WORKER_SCRIPT_PATH="/usr/local/bin/ytlive-worker.sh" [cite: 1]
CHANNELS_BASE_DIR="/root/data/channels" [cite: 1]
SERVICE_USER="ytlive" [cite: 1]
SERVICE_GROUP="ytlive" [cite: 1]
FFMPEG_JV_DIR="/opt/ffmpeg-johnvansickle" [cite: 1]

# --- Fungsi Logging ---
log_info() { echo -e "\e[32m[INFO]\e[0m $1"; } [cite: 1, 2]
log_warn() { echo -e "\e[33m[PERINGATAN]\e[0m $1"; } [cite: 2]
log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; } [cite: 2, 3]

# --- 1. Konfigurasi Sistem ---
log_info "Mengatur zona waktu dan memperbarui paket..." [cite: 3]
timedatectl set-timezone Asia/Jakarta || log_warn "Gagal mengatur zona waktu." [cite: 3]
apt-get update -y >/dev/null || log_error "Gagal memperbarui daftar paket." [cite: 4]
# Perbaikan: Menggunakan polkitd dan menginstal python3-psutil & python3-requests via apt untuk menghindari error PEP 668
apt-get install -y python3 python3-pip wget tar xz-utils acl polkitd logrotate python3-psutil python3-requests || log_error "Gagal menginstal dependensi." 

# --- 2. Pembaruan Komponen Skrip (Jadwal & Stream Aman) ---
log_info "Memperbarui komponen skrip (jadwal dan stream aktif akan tetap aman)..." 
# Hapus hanya file-file yang akan dibuat ulang oleh installer ini.
# JANGAN sentuh timer (.timer) atau service yang sedang berjalan. [cite: 7]
rm -f /etc/systemd/system/ytlive-stream@.service [cite: 8]
rm -f /etc/systemd/system/ytlive-schedule-start@.service [cite: 8]
rm -f /etc/systemd/system/ytlive-schedule-stop@.service [cite: 8]
rm -f /etc/sudoers.d/ytlive [cite: 8]
rm -f /etc/logrotate.d/ytlive [cite: 8]
rm -f "${PYTHON_SCRIPT_PATH}" [cite: 8]
rm -f "${WORKER_SCRIPT_PATH}" [cite: 8]
log_info "Komponen lama berhasil dihapus, siap untuk diperbarui." [cite: 8]

# --- 3. Instal FFMPEG ---
if [ ! -f "/usr/bin/ffmpeg" ]; [cite: 9]
then [cite: 10]
    log_info "FFMPEG tidak ditemukan, menginstal FFMPEG..." [cite: 10]
    mkdir -p "${FFMPEG_JV_DIR}" [cite: 10]
    cd /tmp [cite: 10]
    wget -q --show-progress "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" [cite: 10]
    tar -xf ffmpeg-release-amd64-static.tar.xz -C "${FFMPEG_JV_DIR}" --strip-components=1 [cite: 10]
    ln -sf "${FFMPEG_JV_DIR}/ffmpeg" /usr/bin/ffmpeg [cite: 10]
    ln -sf "${FFMPEG_JV_DIR}/ffprobe" /usr/bin/ffprobe [cite: 10]
    log_info "FFMPEG berhasil diinstal." [cite: 10]
else [cite: 11]
    log_info "FFMPEG sudah ada, instalasi dilewati." [cite: 11]
fi [cite: 12]

# --- 4. Buat Direktori & Pengguna ---
log_info "Memeriksa direktori, pengguna, dan izin akses..." [cite: 12]
mkdir -p "${CHANNELS_BASE_DIR}" [cite: 12]
id -g "${SERVICE_GROUP}" &>/dev/null || groupadd "${SERVICE_GROUP}" [cite: 12, 13]
id -u "${SERVICE_USER}" &>/dev/null || useradd -r -s /bin/false -g "${SERVICE_GROUP}" "${SERVICE_USER}" [cite: 13]
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${CHANNELS_BASE_DIR}" [cite: 13]
setfacl -m u:${SERVICE_USER}:x /root &>/dev/null || true [cite: 13, 14]
setfacl -m u:${SERVICE_USER}:x /root/data &>/dev/null || true [cite: 14]
log_info "Direktori dan izin akses berhasil dikonfigurasi." [cite: 14]

# --- 5. Buat Aturan Izin Sudo ---
log_info "Membuat aturan Sudo untuk izin service..." [cite: 15]
echo 'ytlive ALL=(ALL) NOPASSWD: /bin/systemctl start ytlive-*, /bin/systemctl stop ytlive-*' | tee /etc/sudoers.d/ytlive [cite: 15, 16]
chmod 0440 /etc/sudoers.d/ytlive [cite: 16]
log_info "Aturan Sudo berhasil dibuat." [cite: 16]

# --- 6. Konfigurasi Log Rotation ---
log_info "Mengkonfigurasi rotasi log otomatis..." [cite: 16]
cat << EOF > "/etc/logrotate.d/ytlive"
/root/data/channels/*/stream.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
log_info "Logrotate untuk ytlive berhasil dikonfigurasi." [cite: 16]

# --- 7. Buat Skrip Pekerja (Bash Worker) ---
log_info "Membuat skrip pekerja di ${WORKER_SCRIPT_PATH}..." [cite: 17]
cat << EOF > "${WORKER_SCRIPT_PATH}"
#!/bin/bash
set -e
CHANNEL_NAME=\$1
# Jalankan (exec) FFMPEG. Perintah FFMPEG diambil dari output Python.
exec \$(/usr/bin/python3 ${PYTHON_SCRIPT_PATH} _internal_get_ffmpeg_cmd "\$CHANNEL_NAME") &>> stream.log
EOF
chmod +x "${WORKER_SCRIPT_PATH}" [cite: 18]

# --- 8. Buat Template Service Systemd ---
log_info "Membuat template service Systemd..." [cite: 18]
cat << EOF > "/etc/systemd/system/ytlive-stream@.service"
[Unit]
Description=YTLive Streamer for %i
[Service]
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${CHANNELS_BASE_DIR}/%i
ExecStart=${WORKER_SCRIPT_PATH} %i
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
cat << EOF > "/etc/systemd/system/ytlive-schedule-start@.service"
[Unit]
Description=Scheduled start for YTLive Streamer channel %i
[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${PYTHON_SCRIPT_PATH} start %i
EOF
cat << EOF > "/etc/systemd/system/ytlive-schedule-stop@.service"
[Unit]
Description=Scheduled stop for YTLive Streamer channel %i
[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${PYTHON_SCRIPT_PATH} stop %i
EOF
systemctl daemon-reload [cite: 18]

# --- 9. Tempatkan Skrip Manajemen (Python CLI) - FINAL ---
log_info "Menempatkan script manajemen Python ke ${PYTHON_SCRIPT_PATH}..." [cite: 18]
cat << 'EOF' > "${PYTHON_SCRIPT_PATH}"
#!/usr/bin/env python3
import os
import sys
import subprocess
import argparse
import shlex
import random
import time
from pathlib import Path
from datetime import datetime, timedelta
import shutil
import re

# ===================================================================
# --- CATATAN PERBAIKAN (CHANGELOG) ---
# ===================================================================
# v22 -> v24: Mengembalikan logika FFMPEG ke versi stabil sebelumnya
#      sesuai permintaan pengguna, dan membuat installer menjadi non-destruktif. [cite: 19]
#      - Mode A & B sekarang selalu menggunakan '-c:v copy' untuk video. [cite: 20]
#      - Installer tidak lagi menghapus jadwal/timer. [cite: 21]
# ===================================================================

# ===================================================================
# --- PUSAT KONFIGURASI ---
# ===================================================================
CHANNELS_DIR = Path("/root/data/channels") [cite: 22]
YOUTUBE_RTMP_URL = "rtmp://a.rtmp.youtube.com/live2" [cite: 22]
MAX_BITRATE = "2500k" [cite: 22]
BUFFER_SIZE = "5000k" [cite: 22]
AUDIO_BITRATE = "128k" [cite: 22]
SERVICE_USER = "ytlive" [cite: 22]
SERVICE_GROUP = "ytlive" [cite: 22]
LIFETIME_TAG = "# LIFETIME_STREAM" [cite: 22]
FFMPEG_PATH = "/usr/bin/ffmpeg" [cite: 22]
SYSTEMD_DIR = Path("/etc/systemd/system") [cite: 22]
# ===================================================================

# --- Kode Warna ---
COLOR_RESET = "\033[0m" [cite: 22]
COLOR_INFO = "\033[0;32m" [cite: 22]
COLOR_WARN = "\033[0;33m" [cite: 22]
COLOR_ERROR = "\033[0;31m" [cite: 22]
COLOR_CYAN = "\033[0;36m" [cite: 22]
COLOR_STATUS_RUNNING = COLOR_INFO [cite: 22]
COLOR_STATUS_STOPPED = COLOR_WARN [cite: 22]
COLOR_STATUS_CRASH = COLOR_ERROR [cite: 22]
# ===================================================================

def print_info(message): print(f"{COLOR_INFO}[INFO]{COLOR_RESET} {message}") [cite: 22]
def print_warn(message): print(f"{COLOR_WARN}[PERINGATAN]{COLOR_RESET} {message}") [cite: 22]
def print_error(message): print(f"{COLOR_ERROR}[ERROR]{COLOR_RESET} {message}") [cite: 22]

def _get_paths(channel_name):
    channel_dir = CHANNELS_DIR / channel_name [cite: 22]
    return {
        "dir": channel_dir, "lock": channel_dir / ".stream.lock", "log": channel_dir / "stream.log",
        "key": channel_dir / "stream_key.txt" [cite: 22, 23]
    }

def _get_channel_mode(paths):
    if not paths["dir"].is_dir(): return "N/A" [cite: 23]
    videos = list(paths["dir"].glob("*.mp4")) + list(paths["dir"].glob("*.mkv")) [cite: 23]
    if not videos or any(v.stat().st_size == 0 for v in videos): return "N/A (Video Kosong)" [cite: 23]
    
    audios = list(paths["dir"].glob("*.mp3")) + list(paths["dir"].glob("*.m4a")) + list(paths["dir"].glob("*.aac")) [cite: 23]
    
    if len(audios) > 0: [cite: 23]
        return "B (Video + Audio Harian)" [cite: 23]
    else: [cite: 23]
        return "A (Video Saja)" [cite: 23]

def _build_ffmpeg_command(paths, mode):
    if not paths["key"].is_file() or paths["key"].stat().st_size == 0: return None [cite: 23, 24]
    key = paths["key"].read_text().strip() [cite: 24]
    videos = sorted(list(paths["dir"].glob("*.mp4")) + list(paths["dir"].glob("*.mkv"))) [cite: 24]
    
    day_of_year = datetime.now().timetuple().tm_yday [cite: 24]
    video = videos[(day_of_year - 1) % len(videos)] [cite: 24]

    cmd_list = [FFMPEG_PATH, "-re", "-fflags", "+genpts", "-stream_loop", "-1", "-i", str(video)] [cite: 24]
    common_out_opts = ["-f", "flv", "-maxrate", MAX_BITRATE, "-bufsize", BUFFER_SIZE, f"{YOUTUBE_RTMP_URL}/{key}"] [cite: 24]

    if mode == "A (Video Saja)": [cite: 24]
        cmd_list.extend(["-c:v", "copy", "-c:a", "copy"]) [cite: 24]
        cmd_list.extend(common_out_opts) [cite: 24]

    elif mode == "B (Video + Audio Harian)": [cite: 24, 25]
        audios = sorted(list(paths["dir"].glob("*.mp3")) + list(paths["dir"].glob("*.m4a")) + list(paths["dir"].glob("*.aac"))) [cite: 25]
        if not audios: return None [cite: 25]
        
        daily_audio_file = audios[(day_of_year - 1) % len(audios)] [cite: 25]
        
        audio_codec_options = [] [cite: 25]
        if daily_audio_file.suffix.lower() in ['.m4a', '.aac']: [cite: 25]
            audio_codec_options = ["-c:a", "copy"] [cite: 25]
        else: # .mp3 [cite: 26]
            audio_codec_options = ["-c:a", "aac", "-b:a", AUDIO_BITRATE] [cite: 26]

        cmd_list.extend(["-stream_loop", "-1", "-i", str(daily_audio_file), 
                         "-map", "0:v:0", "-map", "1:a:0", 
                         "-c:v", "copy"] + audio_codec_options) [cite: 26]
        cmd_list.extend(common_out_opts) [cite: 27]
    else: [cite: 27]
        return None [cite: 27]
    
    return cmd_list [cite: 27]

def handle_start(args):
    paths = _get_paths(args.channel) [cite: 27]
    if not paths["dir"].is_dir(): return print_error(f"Channel '{args.channel}' tidak ditemukan.") [cite: 27]
    if subprocess.run(['systemctl', 'is-active', '--quiet', f"ytlive-stream@{args.channel}.service"]).returncode == 0: [cite: 27]
        return print_warn(f"Service untuk '{args.channel}' sudah berjalan.") [cite: 27]
    paths["lock"].write_text(LIFETIME_TAG) [cite: 27]
    try: [cite: 27]
        subprocess.run(['sudo', 'systemctl', 'start', f"ytlive-stream@{args.channel}.service"], check=True) [cite: 27]
        print_info(f"Streaming '{args.channel}' dimulai via Systemd.") [cite: 27]
        if (SYSTEMD_DIR / f"ytlive-schedule-start@{args.channel}.timer").exists(): [cite: 27, 28]
            print_warn("Jadwal yang ada untuk channel ini TIDAK dihapus.") [cite: 28]
    except subprocess.CalledProcessError: [cite: 28]
        print_error(f"Gagal memulai service. Cek log dengan: ytlive debug {args.channel}") [cite: 28, 29]

def handle_stop(args, quiet=False):
    subprocess.run(['sudo', 'systemctl', 'stop', f"ytlive-stream@{args.channel}.service"], check=False, capture_output=True) [cite: 29]
    paths = _get_paths(args.channel) [cite: 29]
    paths["lock"].unlink(missing_ok=True) [cite: 29]
    if not quiet: print_info(f"Stream '{args.channel}' dihentikan.") [cite: 29]

def handle_list(args):
    print(f"{'NAMA CHANNEL':<25} {'MODE':<28} {'STATUS':<20} {'JADWAL'}") [cite: 29]
    print("-" * 100) [cite: 29]
    if not CHANNELS_DIR.is_dir(): return [cite: 29]
    timers_output = subprocess.run(['systemctl', 'list-timers', 'ytlive-schedule-*', '--no-legend', '--all'], capture_output=True, text=True).stdout [cite: 29]
    timers = [line.split() for line in timers_output.splitlines() if 'ytlive-schedule' in line] [cite: 29]
    for channel_dir in sorted(CHANNELS_DIR.iterdir()): [cite: 29]
        if not channel_dir.is_dir(): continue [cite: 29, 30]
        ch_name, paths = channel_dir.name, _get_paths(channel_dir.name) [cite: 30]
        mode = _get_channel_mode(paths) [cite: 30]
        status, jadwal = f"{COLOR_STATUS_STOPPED}[ STOPPED ]{COLOR_RESET}", "Manual" [cite: 30]
        start_timer = next((t for t in timers if f"ytlive-schedule-start@{ch_name}.timer" in t), None) [cite: 30]
        stop_timer = next((t for t in timers if f"ytlive-schedule-stop@{ch_name}.timer" in t), None) [cite: 30]
        is_scheduled = start_timer and stop_timer [cite: 30]
        if subprocess.run(['systemctl', 'is-active', '--quiet', f"ytlive-stream@{ch_name}.service"]).returncode == 0: [cite: 30, 31]
            status = f"{COLOR_STATUS_RUNNING}[ RUNNING ]{COLOR_RESET}" [cite: 31]
        elif paths['lock'].exists() and not is_scheduled: [cite: 31]
             status = f"{COLOR_STATUS_CRASH}[  CRASH  ]{COLOR_RESET}" [cite: 31]
        if is_scheduled: [cite: 31]
            try: [cite: 31]
                start_time_str = start_timer[2]; stop_time_str = stop_timer[2] [cite: 31, 32]
                start_time = datetime.strptime(start_time_str, '%H:%M:%S').strftime('%H:%M') [cite: 32]
                stop_time = datetime.strptime(stop_time_str, '%H:%M:%S').strftime('%H:%M') [cite: 32]
                jadwal = f"{start_time} - {stop_time}" [cite: 32]
            except (ValueError, IndexError): [cite: 32]
                jadwal = "Terjadwal (Error Parsing)" [cite: 32]
        elif paths["lock"].exists(): [cite: 32, 33]
            jadwal = "Manual/Lifetime" [cite: 33]
        print(f"{ch_name:<25} {COLOR_CYAN}{mode:<28}{COLOR_RESET} {status:<20} {jadwal}") [cite: 33]
    print("-" * 100) [cite: 33]

def handle_timers(args):
    print_info("Menampilkan Jadwal Timer Systemd untuk YTLive...") [cite: 33]
    print("-" * 70) [cite: 33]
    subprocess.run(['systemctl', 'list-timers', 'ytlive-schedule-*', '--no-pager']) [cite: 33]
    print("-" * 70) [cite: 33]

def handle_create(args):
    paths = _get_paths(args.channel) [cite: 33]
    if paths["dir"].exists(): print_info(f"Channel '{args.channel}' sudah ada."); return [cite: 33, 34]
    paths["dir"].mkdir(parents=True, exist_ok=True); paths["key"].touch() [cite: 34]
    subprocess.run(['chown', '-R', f'{SERVICE_USER}:{SERVICE_GROUP}', str(paths["dir"])]) [cite: 34]
    print_info(f"Channel '{args.channel}' dibuat di: {paths['dir']}") [cite: 34]

def handle_delete(args):
    paths = _get_paths(args.channel) [cite: 34]
    if not paths["dir"].exists(): return print_error(f"Channel '{args.channel}' tidak ditemukan.") [cite: 34]
    handle_stop(args, quiet=True); handle_unschedule(args, quiet=True) [cite: 34, 35]
    if input(f"{COLOR_WARN}Anda yakin ingin menghapus '{args.channel}'? Ketik 'DELETE': {COLOR_RESET}") == "DELETE": [cite: 35]
        shutil.rmtree(paths["dir"]); print_info(f"Channel '{args.channel}' dihapus.") [cite: 35, 36]

def handle_log(args):
    log_file = _get_paths(args.channel)["log"] [cite: 36]
    if not log_file.exists(): return print_info(f"Log file untuk '{args.channel}' tidak ditemukan.") [cite: 36]
    print(f"-> Menampilkan log untuk '{args.channel}' (Ctrl+C untuk keluar)...") [cite: 36]
    try: [cite: 36]
        with subprocess.Popen(['tail', '-f', str(log_file)]) as proc: [cite: 36]
            proc.wait() [cite: 36]
    except KeyboardInterrupt: [cite: 36]
        print("\nKeluar dari mode log.") [cite: 36]

def handle_status(args):
    paths = _get_paths(args.channel) [cite: 36]
    if not paths["dir"].is_dir(): return print_error(f"Channel '{args.channel}' tidak ditemukan.") [cite: 36]
    print("-" * 60); print(f"Status Detail untuk Channel: {COLOR_CYAN}{args.channel}{COLOR_RESET}") [cite: 36, 37]
    mode = _get_channel_mode(paths); print(f"  - Mode             : {mode}") [cite: 37, 38]
    status_str = f"{COLOR_STATUS_STOPPED}STOPPED{COLOR_RESET}" [cite: 38]
    if Path(f"/etc/systemd/system/ytlive-stream@{args.channel}.service").exists(): [cite: 38]
        if subprocess.run(['systemctl', 'is-active', '--quiet', f"ytlive-stream@{args.channel}.service"]).returncode == 0: status_str = f"{COLOR_STATUS_RUNNING}RUNNING{COLOR_RESET}" [cite: 38]
        elif paths['lock'].exists(): status_str = f"{COLOR_STATUS_CRASH}CRASHED{COLOR_RESET}" [cite: 38]
    print(f"  - Status Service   : {status_str}") [cite: 38]
    print("  - Log Terakhir     : ") [cite: 38]
    if not paths["log"].exists(): print("    (Log file tidak ditemukan)") [cite: 38]
    else: [cite: 38, 39]
        try: [cite: 39]
            for line in paths["log"].read_text().splitlines()[-15:]: print(f"    {line}") [cite: 39]
        except Exception as e: print(f"    (Gagal membaca log: {e})") [cite: 39]
    print("-" * 60) [cite: 39]

def handle_debug(args):
    service_name = f"ytlive-stream@{args.channel}.service" [cite: 39]
    print("-" * 60); print(f"Menampilkan log Systemd (journalctl) untuk: {COLOR_CYAN}{service_name}{COLOR_RESET}") [cite: 39, 40]
    print("Log ini sangat penting jika status channel adalah [CRASHED]"); print("-" * 60) [cite: 40, 41]
    try: [cite: 41]
        subprocess.run(['journalctl', '-u', service_name, '-f', '--no-pager']) [cite: 41]
    except KeyboardInterrupt: [cite: 41]
        print("\nKeluar dari mode debug.") [cite: 41]
    print("-" * 60) [cite: 41]

def _clean_single_channel(name, quiet=False):
    paths = _get_paths(name) [cite: 41]
    if subprocess.run(['systemctl', 'is-active', '--quiet', f"ytlive-stream@{name}.service"]).returncode == 0: [cite: 41]
        if not quiet: print_warn(f"Melewatkan pembersihan '{name}' karena sedang berjalan.") [cite: 41]
        return False [cite: 41]
    if not quiet: print_info(f"Membersihkan file sementara untuk '{name}'...") [cite: 41]
    for f in [paths["log"], paths["lock"]]: [cite: 41, 42]
        if f.exists(): [cite: 42]
            f.unlink() [cite: 42]
            if not quiet: print(f"  -> Dihapus: {f.name}") [cite: 42]
    return True [cite: 42]

def handle_schedule(args):
    _clean_single_channel(args.channel) [cite: 42]
    paths = _get_paths(args.channel) [cite: 42]
    if "N/A" in _get_channel_mode(paths): return print_error(f"Mode channel tidak valid atau file media kosong. Mode terdeteksi: '{_get_channel_mode(paths)}'") [cite: 42]
    try: [cite: 42]
        start_dt = datetime.strptime(args.start_time, '%H:%M') [cite: 42]
        if args.stop_time: [cite: 42, 43]
            stop_dt = datetime.strptime(args.stop_time, '%H:%M') [cite: 43]
        else: [cite: 43]
            stop_dt = start_dt + timedelta(hours=17, minutes=59) [cite: 43]
    except ValueError: [cite: 43]
        return print_error("Format waktu salah. Gunakan HH:MM. Contoh: 08:00 atau 21:30") [cite: 43, 44]
    
    handle_unschedule(args, quiet=True) [cite: 44]
    paths["lock"].unlink(missing_ok=True) [cite: 44]
    ch_name = args.channel [cite: 44]
    start_cal = f"*-*-* {start_dt.strftime('%H:%M:%S')}" [cite: 44]
    stop_cal = f"*-*-* {stop_dt.strftime('%H:%M:%S')}" [cite: 44]
    start_timer_content = f"""[Unit]\nDescription=Timer to start YTLive channel {ch_name}\n[Timer]\nOnCalendar={start_cal}\nPersistent=true\nUnit=ytlive-schedule-start@{ch_name}.service\n[Install]\nWantedBy=timers.target""" [cite: 44]
    stop_timer_content = f"""[Unit]\nDescription=Timer to stop YTLive channel {ch_name}\n[Timer]\nOnCalendar={stop_cal}\nPersistent=true\nUnit=ytlive-schedule-stop@{ch_name}.service\n[Install]\nWantedBy=timers.target""" [cite: 44]
    (SYSTEMD_DIR / f"ytlive-schedule-start@{ch_name}.timer").write_text(start_timer_content) [cite: 44]
    (SYSTEMD_DIR / f"ytlive-schedule-stop@{ch_name}.timer").write_text(stop_timer_content) [cite: 44]
    try: [cite: 44]
        subprocess.run(['systemctl', 'daemon-reload'], check=True) [cite: 44]
        subprocess.run(['systemctl', 'enable', f"ytlive-schedule-start@{ch_name}.timer", f"ytlive-schedule-stop@{ch_name}.timer"], check=True, capture_output=True) [cite: 44]
        subprocess.run(['systemctl', 'start', f"ytlive-schedule-start@{ch_name}.timer", f"ytlive-schedule-stop@{ch_name}.timer"], check=True, capture_output=True) [cite: 44, 45]
        print_info(f"Jadwal '{ch_name}' berhasil diatur: {start_dt.strftime('%H:%M')} - {stop_dt.strftime('%H:%M')}") [cite: 45]
    except subprocess.CalledProcessError as e: [cite: 45]
        print_error(f"Gagal mengatur timer systemd. Detail: {e.stderr.decode()}") [cite: 45, 46]

def handle_unschedule(args, quiet=False):
    ch_name = args.channel [cite: 46]
    start_timer = f"ytlive-schedule-start@{ch_name}.timer" [cite: 46]
    stop_timer = f"ytlive-schedule-stop@{ch_name}.timer" [cite: 46]
    if not (SYSTEMD_DIR / start_timer).exists(): [cite: 46]
        if not quiet: print_info(f"Tidak ada jadwal untuk '{ch_name}'.") [cite: 46]
        return [cite: 46]
    subprocess.run(['systemctl', 'stop', start_timer, stop_timer], capture_output=True, check=False) [cite: 46]
    subprocess.run(['systemctl', 'disable', start_timer, stop_timer], capture_output=True, check=False) [cite: 46]
    (SYSTEMD_DIR / start_timer).unlink(missing_ok=True) [cite: 46]
    (SYSTEMD_DIR / stop_timer).unlink(missing_ok=True) [cite: 46]
    subprocess.run(['systemctl', 'daemon-reload'], capture_output=True, check=False) [cite: 46]
    if not quiet: print_info(f"Jadwal untuk '{ch_name}' dihapus.") [cite: 46]

def handle_clean(args): [cite: 46, 47]
    if args.channel.lower() == 'all': [cite: 47]
        for d in CHANNELS_DIR.iterdir(): [cite: 47]
            if d.is_dir(): _clean_single_channel(d.name) [cite: 47]
    else: [cite: 47]
        _clean_single_channel(args.channel) [cite: 47]

def handle_lifetime(args):
    paths = _get_paths(args.channel) [cite: 47]
    if subprocess.run(['systemctl', 'is-active', '--quiet', f"ytlive-stream@{args.channel}.service"]).returncode != 0: [cite: 47]
        handle_start(args) [cite: 47]
    handle_unschedule(args, quiet=True) [cite: 47]
    paths["lock"].write_text(LIFETIME_TAG) [cite: 47]
    print_info(f"Stream '{args.channel}' telah diatur ke mode LIFETIME (permanen).") [cite: 47]

def _internal_get_ffmpeg_cmd(args):
    paths = _get_paths(args.channel) [cite: 47]
    mode = _get_channel_mode(paths) [cite: 47, 48]
    cmd = _build_ffmpeg_command(paths, mode) [cite: 48]
    if cmd: print(" ".join(shlex.quote(c) for c in cmd)) [cite: 48]
    else: [cite: 48]
        with open(paths["log"], 'a') as f: f.write("ERROR: Gagal membangun perintah FFMPEG.\n") [cite: 48]
        sys.exit(1) [cite: 48]

def main():
    parser = argparse.ArgumentParser(description="YTLive Streamer", formatter_class=argparse.RawTextHelpFormatter) [cite: 48]
    subparsers = parser.add_subparsers(dest='command'); subparsers.required = True [cite: 48, 49]
    handler_map = {'start': handle_start, 'stop': handle_stop, 'list': handle_list, 'status': handle_status, 'create': handle_create, 'delete': handle_delete, 'log': handle_log, 'schedule': handle_schedule, 'unschedule': handle_unschedule, 'clean': handle_clean, 'lifetime': handle_lifetime, 'debug': handle_debug, 'timer': handle_timers} [cite: 49]
    if len(sys.argv) > 1 and sys.argv[1].startswith('_internal'): [cite: 49]
        internal_parser = argparse.ArgumentParser() [cite: 49]
        internal_parser.add_argument('command'); internal_parser.add_argument('channel') [cite: 49, 50]
        args = internal_parser.parse_args() [cite: 50]
        if args.command == '_internal_get_ffmpeg_cmd': _internal_get_ffmpeg_cmd(args) [cite: 50]
        return [cite: 50]
    if len(sys.argv) == 2 and sys.argv[1] not in handler_map and not sys.argv[1].startswith('-'): [cite: 50]
        if (CHANNELS_DIR / sys.argv[1]).is_dir(): sys.argv.insert(1, 'status') [cite: 50]
        else: print_error(f"Channel '{sys.argv[1]}' tidak ditemukan."); sys.exit(1) [cite: 50, 51]
    p_start = subparsers.add_parser('start', help='Mulai stream. Contoh: ytlive start <channel>'); p_start.add_argument('channel') [cite: 51, 52]
    p_stop = subparsers.add_parser('stop', help='Hentikan stream. Contoh: ytlive stop <channel>'); p_stop.add_argument('channel') [cite: 52, 53]
    p_list = subparsers.add_parser('list', help='Tampilkan status semua channel.') [cite: 53]
    p_timer = subparsers.add_parser('timer', help='Tampilkan detail jadwal timer systemd.') [cite: 53]
    p_status = subparsers.add_parser('status', help='Tampilkan status detail. Contoh: ytlive status <channel>'); p_status.add_argument('channel') [cite: 53, 54]
    p_create = subparsers.add_parser('create', help='Buat channel baru. Contoh: ytlive create <channel>'); p_create.add_argument('channel') [cite: 54, 55]
    p_delete = subparsers.add_parser('delete', help='Hapus channel. Contoh: ytlive delete <channel>'); p_delete.add_argument('channel') [cite: 55, 56]
    p_log = subparsers.add_parser('log', help='Tampilkan log realtime. Contoh: ytlive log <channel>'); p_log.add_argument('channel') [cite: 56, 57]
    p_debug = subparsers.add_parser('debug', help='Tampilkan log realtime systemd. Contoh: ytlive debug <channel>'); p_debug.add_argument('channel') [cite: 57, 58]
    p_schedule = subparsers.add_parser('schedule', help='Jadwalkan stream. Contoh: ytlive schedule <channel> 08:00 [22:00]'); p_schedule.add_argument('channel'); p_schedule.add_argument('start_time'); p_schedule.add_argument('stop_time', nargs='?', default=None) [cite: 58, 59]
    p_unschedule = subparsers.add_parser('unschedule', help='Hapus jadwal. Contoh: ytlive unschedule <channel>'); p_unschedule.add_argument('channel') [cite: 59, 60]
    p_clean = subparsers.add_parser('clean', help='Bersihkan file sementara. Contoh: ytlive clean all'); p_clean.add_argument('channel') [cite: 60, 61]
    p_lifetime = subparsers.add_parser('lifetime', help='Jadikan stream permanen. Contoh: ytlive lifetime <channel>'); p_lifetime.add_argument('channel') [cite: 61, 62]
    for name, func in handler_map.items(): [cite: 62]
        if name in subparsers.choices: subparsers.choices[name].set_defaults(func=func) [cite: 62]
    if len(sys.argv) == 1: [cite: 62]
        parser.print_help(); print("\n" + "="*20 + " STATUS CHANNEL SAAT INI " + "="*20); handle_list(None); sys.exit(0) [cite: 62, 63, 64]
    args = parser.parse_args() [cite: 64]
    args.func(args) [cite: 64]

if __name__ == "__main__": [cite: 64]
    main() [cite: 64]
EOF

chmod +x "${PYTHON_SCRIPT_PATH}" || { log_error "Gagal membuat skrip Python dapat dieksekusi."; exit 1; } [cite: 64, 65]
log_info "Skrip Python berhasil ditempatkan." [cite: 65]
log_info "===================================================" [cite: 65, 66]
log_info "        YTLIVE STREAMER SETUP COMPLETE!" [cite: 66]
log_info "===================================================" [cite: 66, 67]
log_info "Semua perbaikan telah diterapkan. Jalankan 'ytlive' untuk melihat perintah." [cite: 67]
log_info "Selamat melakukan streaming! ✅" [cite: 67]
