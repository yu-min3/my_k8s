FROM python:3.11-slim

# uvインストール
RUN pip install uv

WORKDIR /app

# pyproject.tomlコピーして依存関係インストール
COPY pyproject.toml ./
RUN uv pip install --system -r pyproject.toml

# アプリケーションコピー
COPY . .

EXPOSE 8501

# デフォルトコマンド
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.enableCORS=false"]
