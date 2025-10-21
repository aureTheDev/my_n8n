from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
from pytube import YouTube
from yt_dlp import YoutubeDL
import os
import subprocess

app = FastAPI(debug=True)








DOWNLOADS_DIR = "./downloads"

@app.get("/")
def home():
    return {"msg": "API OK"}

@app.post("/download-video")
def download_video(video_url: str = Query(..., description="URL of the video to download")):
    try:
        # Ensure the downloads directory exists
        if not os.path.exists(DOWNLOADS_DIR):
            os.makedirs(DOWNLOADS_DIR)

        # Try downloading with pytube
        try:
            yt = YouTube(video_url)
            stream = yt.streams.get_highest_resolution()
            file_path = stream.download(output_path=DOWNLOADS_DIR)

            # Convert to MP4 if necessary
            mp4_path = os.path.splitext(file_path)[0] + ".mp4"
            if not file_path.endswith(".mp4"):
                subprocess.run(["ffmpeg", "-i", file_path, mp4_path, "-y"], check=True)
                os.remove(file_path)  # Remove the original file after conversion
                file_path = mp4_path

            # Extract audio as MP3
            mp3_path = os.path.splitext(file_path)[0] + ".mp3"
            subprocess.run(["ffmpeg", "-i", file_path, "-q:a", "0", "-map", "a", mp3_path, "-y"], check=True)

            return {
                "msg": "Video downloaded and converted successfully",
                "video_file": file_path,
                "audio_file": mp3_path,
            }
        except Exception as pytube_error:
            # If pytube fails, fallback to yt-dlp
            ydl_opts = {
                'outtmpl': os.path.join(DOWNLOADS_DIR, '%(title)s.%(ext)s'),
                'format': 'bestvideo+bestaudio/best',
            }
            with YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(video_url, download=True)
                file_path = ydl.prepare_filename(info)

                # Convert to MP4 if necessary
                mp4_path = os.path.splitext(file_path)[0] + ".mp4"
                if not file_path.endswith(".mp4"):
                    subprocess.run(["ffmpeg", "-i", file_path, mp4_path, "-y"], check=True)
                    os.remove(file_path)  # Remove the original file after conversion
                    file_path = mp4_path

                # Extract audio as MP3
                mp3_path = os.path.splitext(file_path)[0] + ".mp3"
                subprocess.run(["ffmpeg", "-i", file_path, "-q:a", "0", "-map", "a", mp3_path, "-y"], check=True)

                return {
                    "msg": "Video downloaded and converted successfully with yt-dlp",
                    "video_file": file_path,
                    "audio_file": mp3_path,
                }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error during download: {str(e)}")