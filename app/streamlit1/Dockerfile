# ファイル名: Dockerfile
FROM python:3.11-slim

RUN pip install --no-cache-dir streamlit

COPY app.py /app/app.py
WORKDIR /app

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.enableCORS=false"]
