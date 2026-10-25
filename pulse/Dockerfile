# One image serves both the API and the web app.  Build from the pulse/ folder:
#   docker build -t pulse .   &&   docker run -p 8000:8000 -e PULSE_PROVIDER=anthropic -e ANTHROPIC_API_KEY=... pulse
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv/pulse

COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

COPY shared shared
COPY web web
COPY backend/app backend/app

# Run as a normal user.
RUN useradd --create-home pulse && chown -R pulse /srv/pulse
USER pulse

WORKDIR /srv/pulse/backend
ENV PORT=8000
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,os;urllib.request.urlopen('http://127.0.0.1:%s/healthz'%os.environ.get('PORT','8000'))"
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
