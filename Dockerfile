# Stage 1: Frontend build
FROM node:18-bullseye AS frontend-builder
WORKDIR /app

# Copy frontend files
COPY app/frontend ./app/frontend

# Install dependencies and build frontend
RUN cd app/frontend && \
    npm install && \
    npm run build

# Stage 2: Backend build
FROM python:3.10-slim-bullseye AS backend-builder
WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl build-essential && \
    rm -rf /var/lib/apt/lists/*

# Install Poetry
RUN pip install --no-cache-dir poetry

# Copy backend files
COPY app/backend ./app/backend
COPY pyproject.toml poetry.lock ./

# Install Python dependencies
RUN poetry config virtualenvs.create false && \
    poetry install --no-interaction --no-ansi

# Stage 3: Final image
FROM python:3.10-slim-bullseye
WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir "uvicorn[standard]"

# Copy built artifacts
COPY --from=frontend-builder /app/app/frontend/dist ./app/frontend/dist
COPY --from=backend-builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=backend-builder /app/app/backend ./app/backend
COPY .env.example .env
COPY run.sh .

# Configure Supervisord
RUN mkdir -p /var/log/supervisor && \
    echo '[supervisord]\n\
nodaemon=true\n\
logfile=/var/log/supervisord.log\n\
logfile_maxbytes=50MB\n\
logfile_backups=10\n\
[program:backend]\n\
command=uvicorn app.backend.main:app --host 0.0.0.0 --port 8000\n\
directory=/app\n\
autorestart=true\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
[program:frontend]\n\
command=npx serve -s app/frontend/dist -l 5173\n\
directory=/app\n\
autorestart=true\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0' > /etc/supervisor/conf.d/supervisord.conf

# Set permissions
RUN chmod +x run.sh

# Expose ports
EXPOSE 8000 5173

# Start application
CMD ["./run.sh"]
