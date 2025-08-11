FROM python:3.11-slim

# uvインストール
RUN pip install uv

WORKDIR /app

# pyproject.tomlコピーして依存関係インストール
COPY pyproject.toml ./
RUN uv pip install --system -r pyproject.toml

# アプリケーションコピー
COPY . .

EXPOSE 8000

# デフォルトコマンド
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]